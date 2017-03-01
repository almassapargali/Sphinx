defmodule Sphinx.Plugs do
  @moduledoc """
  Module with convenient plug functions. You might want to import it in
  your `web.ex` inside `controller` scope.

  As well as, to make sure all your endpoints have authorization performed,
  you may want to include `plug :ensure_authorization` in your pipelines.
  """
  import Plug.Conn

  alias Sphinx.Util

  defp _default_options() do
    [
      actor_fetcher: Application.get_env(:sphinx, :actor_fetcher) || &( &1.assigns[:current_user] ),

      authorizer: nil,

      # repo is called `get!` function with module and id as parameter
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

  @doc """
  Plug for ensuring you've performed authorization (or skipped it). If you haven't
  it would raise `Sphinx.AuthorizationNotPerformedError` when you respond to `conn`.
  """
  def ensure_authorization(conn, _) do
    register_before_send conn, fn conn ->
      if conn.status in 200..399 do
        case conn.private[@authorization_status_key] do
          :skipped -> conn
          :authorized -> conn
          _ ->
            raise Sphinx.AuthorizationNotPerformedError
        end
      else
        conn
      end
    end
  end

  @doc """
  Plug for skipping authorization check if you're using `ensure_authorization`.
  It'd flag `conn`'s authorization status as skipped, and wouldn't perform
  any authorizations or checks afterwards.

  ## Options

  * `:only` - atom or list of atoms to skip. This should correspond to
    controller's action names. Only given actions would be skipped.
  * `:except` - atom or list of atoms to exclude from skipping.

  ## Examples

      defmodule MyApp.UserController do
        use MyApp.Web, :controller

        plug skip_authorization, only: :index

        def index(conn, params) do
          ...
        end
      end

  """
  def skip_authorization(conn, opts) do
    case Util.should_apply?(conn, opts) do
      true -> put_private(conn, @authorization_status_key, :skipped)
      false -> conn
    end
  end

  @doc """
  Main plug for authorizing request. Fetches the current resource, authorizes
  action, action, and resource with authorizer, then either raises `Sphinx.NotAuthorizedError`,
  or flags `conn` as authorized, setting resource to `conn.assigns.resource`.

  ## Fetching resource

  Sphinx take number of steps to fetch current resource.

  1. First of all, it checks if `:resource_fetcher` option is passed. If it is,
    it'd be called with `conn` and resulting value would be used as `resource`.

  2. If `:resource_fetcher` hasn't passed, Sphinx need to know module of resource
    to fetch it. It can be passed through `:model` option, or can be inferred from
    controller name by removing trailing `Controller`, and then, if required, by removing `Api`
    namespace from it. For example, any of `[MyApp.UserController, MyApp.Api.UserController]`
    infers to `MyApp.User`.

  3. If action of request is one of `[:index, :create, :new]` (collection actions),
    authorization would be done using module itself. You can expand this list by passing
    `:collection` option when calling plug.

  4. At last, Sphinx gets id of resource from `params` using `:id_key` option (by default,
    it's "id"), then gets resource from repo calling: `repo.get!(model, id)`. So,
    if your path looks like `users/:user_id/posts/:id`, and you want to authorize by user,
    you'd need to pass `[id_key: "user_id", model: User]` as options.

  ## Getting actor

  By default, actor is taken from `:current_user` field of `conn` assigns. You can override
  this by providing `:actor_fetcher` function or {Module, :function_name} pair either in
  app's config or when calling plug. This function would be called with current `conn` and
  result will be passed to authorizer as an actor.

  ## Action

  Action is the name of controller function which handles current request. Common REST actions
  are: `[:index, :show, :create, :update, :delete]`.

  ## Authorizer

  Aithorizer is module for authorizing action with given actor and resource. You can either
  pass it when calling `:authorize`, or it will be inferred from current controller's name
  by replacing trailing "Controller" with "Authorizer". For example, if your controller is
  `MyApp.Api.UserController`, it first tries to load `MyApp.Api.UserAuthorizer`, then
  `MyApp.UserAuthorizer`. Only `Api` namespace is dropped from inferring, all other namespaces
  are preserved. Example authorizer:

      defmodule MyApp.UserAuthorizer do
        def authorize?(_, :index, Post), do: true # index is public

        def authorize?(%User{id: id}, :update, %Post{author_id: id}), do: true # author can update own posts
        def authorize?(_, :update, _),
          do: {false, "Post editing limited to post authors only"} # fail with custom reason

        def authorize?(_, :delete_all, Post), do: false # fail with default message, see `Sphinx.NotAuthorizedError` docs
      end

  ## Options

  All options are optional if naming conventions are preserved and repo is given in app's config.

  * `:actor_fetcher` - function/module-function pair to use for getting actor, called with conn.
  * `:authorizer` - authorize module to use.
  * `:resource_fetcher` - function, or keyword with function values. If given function,
    all actions will use that function to fetch resource, if given keyword, functions
    for existing action keys will be used when exists, otherwise default Sphinx fetching
    is used. Function called with conn, and passes whatever it receives to authorizer as resource.
  * `:collection` - atom or list of atoms corresponding to actions, which should authorized by
    module itself, instead of instance of module. By default, `[:index, :new, :create]` actions
    always authorized by module.
  * `:repo` - repo from where Sphinx gets resource. It's called `get!` function with module, and id
    as parameters (like Ecto's Repo).
  * `:model` - module of resource for fetching and authorizing with it.
  * `:id_key` - key for id param, in `conn.params`. By default it's "id", by you may want
    to probably change this for nested resources authorized by parents.
  * `:only` - atom or list of atoms to authorize. This should correspond to
    controller's action names. Only given actions would be authorized.
  * `:except` - atom or list of atoms to exclude from authorizing.

  """
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

    actor = fetch_actor(conn, opts[:actor_fetcher])

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

  defp fetch_actor(conn, fetcher) when is_function(fetcher), do: fetcher.(conn)
  defp fetch_actor(conn, {module, function}) do
    apply(module, function, [conn])
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

      # load resource from repo
      model && opts[:id_key] && opts[:repo] -> opts[:repo].get!(model, conn.params[opts[:id_key]])

      is_nil(opts[:repo]) ->
        raise Sphinx.MissingOptionError, message: "Value for repo option is missing.
          Please define it either when calling plug, or in app configs."

      is_nil(opts[:id_key]) ->
        raise Sphinx.MissingOptionError, message: "Value for :id_key is missing"

      true ->
        raise Sphinx.MissingOptionError, message: "Please define model key when calling plug.
          Alternatively, follow naming convention, i.e. UserController -> User"
    end
  end
end
