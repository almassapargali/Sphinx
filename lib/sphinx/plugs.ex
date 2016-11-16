defmodule Sphinx.Plugs do
  import Plug.Conn

  alias Sphinx.Util

  defp _default_options() do
    [
      actor_fetcher: Application.get_env(:sphinx, :actor_fetcher) || &( &1.assigns[:current_user] ),

      # note: passing common authorizer on config would turn of inferring
      authorizer: Application.get_env(:sphinx, :authorizer),

      # this one is required
      repo: Application.get_env(:sphinx, :repo),

      # we can fetch resource either by id and module using `repo.get!(model, id)`, or by calling
      # `resource_fetcher` with conn
      id_key: "id",
      model: nil,

      resource_fetcher: nil,

      # actions, which are should authorized by Module itself, not by instance of it
      # `:index`, `:new`, `:create` actions are always authorized by Module itself, you should
      # provide `resource_fetcher` if you don't want this behaviour.
      collection: []
    ]
  end

  @authorization_status_key :sphinx_authorization_status

  def ensure_authorization(conn, _) do
    register_before_send conn, fn conn ->
      case conn.private[@authorization_status_key] do
        :skipped -> conn
        :authorized -> conn
        _ ->
          raise Sphinx.AuthorizationNotPerformedError
      end
    end
  end

  def skip_authorization(conn, opts) do
    case Util.should_apply?(conn, opts) do
      true -> put_private(conn, @authorization_status_key, :skipped)
      false -> conn
    end
  end

  def authorize(conn, opts) do
    cond do
      # check if it's already skipped
      conn.private[@authorization_status_key] == :skipped -> conn

      # if we should apply action
      Util.should_apply?(conn, opts) -> _authorize(conn, opts)

      # otherwise, just pass conn
      true -> conn
    end
  end

  defp _authorize(conn, opts) do
    opts = Keyword.merge(_default_options(), opts)

    if is_nil(opts[:repo]) do
      raise Sphinx.MissingOptionError, message: "Value for repo option is missing.
        Please define it either when calling plug, or in app configs."
    end

    actor = opts[:actor_fetcher].(conn)

    authorizer = get_authorizer(conn, opts[:authorizer])

    if is_nil(authorizer) do
      raise Sphinx.MissingOptionError, message: "Please define authorizer key either in plug, or app configs.
        Alternatively, follow naming convention, i.e. UserController -> UserAuthorizer"
    end

    resource = fetch_resource(conn, opts)

    case authorizer.authorize?(actor, conn.private.phoenix_action, resource) do
      true ->
        conn
        |> assign(:resource, resource)
        |> put_private(@authorization_status_key, :authorized)

      false -> raise Sphinx.NotAuthorizedError

      {false, reason} -> raise Sphinx.NotAuthorizedError, message: reason
    end
  end

  defp get_authorizer(conn, nil), do: Util.infer_module_with_suffix(conn, "Authorizer")
  defp get_authorizer(_, authorizer), do: authorizer

  defp fetch_resource(conn, opts) do
    action = conn.private.phoenix_action
    collection_actions = [:index, :new, :create] ++ List.wrap(opts[:collection])
    model = opts[:model] || Util.infer_module_with_suffix(conn, "")

    cond do
      # we've got a resource_fetcher
      is_function(opts[:resource_fetcher]) -> opts[:resource_fetcher].(conn)

      # we've got a resource_fetcher for given action
      Keyword.keyword?(opts[:resource_fetcher]) && Keyword.has_key?(opts[:resource_fetcher], action) ->
        Keyword.get(opts[:resource_fetcher], action).(conn)

      # authorize this one by model itself
      model && action in collection_actions -> model

      # load resource from repo, repo is made sure to exist here
      model && opts[:id_key] -> opts[:repo].get!(model, conn.params[opts[:id_key]])

      model ->
        raise Sphinx.MissingOptionError, message: "Value for :id_key is missing"

      true ->
        raise Sphinx.MissingOptionError, message: "Please define model key when calling plug.
          Alternatively, follow naming convention, i.e. UserController -> User"
    end
  end
end
