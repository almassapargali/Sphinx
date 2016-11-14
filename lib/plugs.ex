defmodule Sphinx.Plugs do
  import Plug.Conn

  @config Application.get_all_env(:sphinx)

  @default_options [
    actor_fetcher: @config[:actor_fetcher] || &Sphinx.Plugs._default_current_user_fetcher/1,
    authorizer: @config[:authorizer],
    repo: @config[:repo],

    # we can fetch resource either by id and module using repo.get!(model, id), or by calling
    # resource_fetcher with conn
    id_key: "id",
    model: nil,
    collection: [],

    resource_fetcher: nil
  ]

  @authorization_status_key :sphinx_authorization_status

  def _default_current_user_fetcher(conn), do: conn.assigns[:current_user]

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

  def skip_authorization(conn, _) do
    put_private(conn, @authorization_status_key, :skipped)
  end

  def authorize(conn, opts) do
    opts = Keyword.merge(@default_options, opts)

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

      false -> raise Sphinx.NotAuthorized

      {false, reason} -> raise Sphinx.NotAuthorized, message: reason
    end
  end

  defp get_authorizer(conn, nil), do: infer_module_with_suffix(conn, "Authorizer")
  defp get_authorizer(_, authorizer), do: authorizer

  defp fetch_resource(conn, opts) do
    action = conn.private.phoenix_action
    collection_actions = [:index, :new, :create] ++ List.wrap(opts[:collection])
    model = opts[:model] || infer_module_with_suffix(conn, "")

    cond do
      is_function(opts[:resource_fetcher]) -> opts[:resource_fetcher].(conn)

      Keyword.keyword?(opts[:resource_fetcher]) && Keyword.has_key?(opts[:resource_fetcher], action) ->
        Keyword.get(opts[:resource_fetcher], action).(conn)

      model && action in collection_actions -> model

      model && opts[:id_key] -> opts[:repo].get!(model, conn.params[opts[:id_key]])

      model ->
        raise Sphinx.MissingOptionError, message: "Value for :id_key is missing"

      true ->
        raise Sphinx.MissingOptionError, message: "Please define model key when calling plug.
          Alternatively, follow naming convention, i.e. UserController -> User"
    end
  end

  defp infer_module_with_suffix(%Plug.Conn{private: %{phoenix_controller: controller}}, suffix) do
    possible_module = controller |> to_string() |> String.replace_suffix("Controller", suffix)

    # try also by removing .Api. namespace
    [possible_module, String.replace(possible_module, ".Api.", ".")]
    |> Enum.map(&String.to_atom/1)
    |> Enum.find(&Code.ensure_loaded?/1)
  end
end
