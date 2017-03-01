defmodule User do
  defstruct id: 1
end

defmodule Profile do
  defstruct id: 1
end

defmodule Repo do
  def get!(User, 0), do: raise "not found"
  def get!(User, id), do: %User{id: id}
  def get!(Profile, id), do: %Profile{id: id}
end

defmodule UserController do end

defmodule UserAuthorizer do
  def authorize?(%User{}, :index, User), do: true
  def authorize?(%User{}, :list, User), do: true

  def authorize?(%User{}, :show, %User{}), do: true
  def authorize?(%User{}, :show, %Profile{}), do: true

  def authorize?(%User{id: id}, :delete, %User{id: id}), do: true
  def authorize?(%User{}, :delete, %User{}), do: false
  def authorize?(%User{}, :hurt, %User{}), do: {false, "not allowed"}
end

defmodule SphinxTest do
  use ExUnit.Case

  Application.put_env :sphinx, :repo, Repo

  import Plug.Conn
  import Sphinx.Plugs

  doctest Sphinx

  setup do
    user = %User{id: 1}
    conn = %Plug.Conn{}
    |> put_private(:phoenix_controller, UserController)
    |> assign(:current_user, user)

    {:ok, conn: conn, user: user}
  end

  # Resource to authorize tests

  test "it authorizes index by Module itself", %{conn: conn} do
    conn = conn
    |> put_private(:phoenix_action, :index)
    |> authorize([])

    assert conn.assigns.resource == User
  end

  test "it authorizes collection actions by Module itself", %{conn: conn} do
    conn = conn |> put_private(:phoenix_action, :list)

    assert authorize(conn, [collection: :list]).assigns.resource == User
    assert authorize(conn, [collection: [:list]]).assigns.resource == User
  end

  test "it raises not found if resource for given id not found", %{conn: conn} do
    conn = conn
    |> put_private(:phoenix_action, :show)
    |> Map.put(:params, %{"id" => 0})

    assert_raise RuntimeError, "not found", fn ->
      authorize(conn, [])
    end
  end

  test "it authorizes resource fetched with id param by default", %{conn: conn} do
    conn = conn
    |> put_private(:phoenix_action, :show)
    |> Map.put(:params, %{"id" => 2})
    |> authorize([])

    assert conn.assigns.resource == %User{id: 2}
  end

  test "it authorizes resource fetched with id_key param if given", %{conn: conn} do
    conn = conn
    |> put_private(:phoenix_action, :show)
    |> Map.put(:params, %{"user_id" => 5})
    |> authorize(id_key: "user_id")

    assert conn.assigns.resource == %User{id: 5}
  end

  test "it uses given model module, still inferring authorizer from controller", %{conn: conn} do
    conn = conn
    |> put_private(:phoenix_action, :show)
    |> Map.put(:params, %{"id" => 2})
    |> authorize(model: Profile)

    assert conn.assigns.resource == %Profile{id: 2}
  end

  test "it uses given resource_fetcher", %{conn: conn} do
    defmodule TupleAuthorizer do
      def authorize?(%User{}, :action, {:ok, :value}), do: true
    end

    conn = conn
    |> put_private(:phoenix_action, :action)
    |> authorize(authorizer: TupleAuthorizer, resource_fetcher: fn _ -> {:ok, :value} end)

    assert conn.assigns.resource == {:ok, :value}
  end

  test "it uses given resource_fetcher per action", %{conn: conn} do
    defmodule SomeAuthorizer do
      def authorize?(%User{}, :show, %User{}), do: true
      def authorize?(%User{}, :other, %Profile{}), do: true
    end

    opts = [authorizer: SomeAuthorizer, resource_fetcher: [other: fn _ -> %Profile{} end]]

    show_conn = conn
    |> put_private(:phoenix_action, :show)
    |> Map.put(:params, %{"id" => 2})
    |> authorize(opts)

    assert show_conn.assigns.resource == %User{id: 2}

    other_conn = conn
    |> put_private(:phoenix_action, :other)
    |> authorize(opts)

    assert other_conn.assigns.resource == %Profile{}
  end

  # Authorizer tests

  test "it uses given authorizer", %{conn: conn} do
    defmodule GivenAuthorizer do
      def authorize?(%User{}, :only_my_action, %User{}), do: {false, "check"}
    end

    conn = conn
    |> put_private(:phoenix_action, :only_my_action)
    |> Map.put(:params, %{"id" => 2})

    assert_raise Sphinx.NotAuthorizedError, "check", fn ->
      authorize(conn, authorizer: GivenAuthorizer)
    end
  end

  # Actor tests

  test "it uses actor_fetcher if passed", %{conn: conn} do
    defmodule ProfileAuthorizer do
      def authorize?(%Profile{}, :index, User), do: true
    end

    conn
    |> put_private(:phoenix_action, :index)
    |> authorize(authorizer: ProfileAuthorizer, actor_fetcher: fn _ -> %Profile{} end)

    # the fact that it haven't rised already an assertion
  end

  test "it calls actor_fetcher pair if passed", %{conn: conn} do
    defmodule ModProfileAuthorizer do
      def authorize?(%Profile{}, :index, User), do: true
    end

    defmodule Fetcher do
      def fetch(_), do: %Profile{}
    end

    conn
    |> put_private(:phoenix_action, :index)
    |> authorize(authorizer: ModProfileAuthorizer, actor_fetcher: {Fetcher, :fetch})

    # the fact that it haven't rised already an assertion
  end

  # Action tests

  test "it passes phoenix_action as action to authorizer", %{conn: conn} do
    defmodule FailingAuthorizer do
      def authorize?(%User{}, :my_action, %User{}), do: {false, "my_action passed"}
    end

    conn = conn
    |> put_private(:phoenix_action, :my_action)
    |> Map.put(:params, %{"id" => 2})

    assert_raise Sphinx.NotAuthorizedError, "my_action passed", fn ->
      authorize(conn, authorizer: FailingAuthorizer)
    end
  end

  # Authorization failing tests

  test "it should raise with default message when authorizer returns false", %{conn: conn, user: user} do
    conn = conn
    |> put_private(:phoenix_action, :delete)
    |> Map.put(:params, %{"id" => user.id + 1})

    assert_raise Sphinx.NotAuthorizedError, "You do not have access to this resource.", fn ->
      authorize(conn, [])
    end
  end

  test "it should raise with reason message when authorizer returns {false, reason}", %{conn: conn} do
    conn = conn
    |> put_private(:phoenix_action, :hurt)
    |> Map.put(:params, %{"id" => 2})

    assert_raise Sphinx.NotAuthorizedError, "not allowed", fn ->
      authorize(conn, [])
    end
  end

  # Authorization ensuring tests

  test "it should raise when responding without authorization after ensure_authorization called", %{conn: conn} do
    conn = conn
    |> ensure_authorization([])
    |> Plug.Adapters.Test.Conn.conn(:get, "/index", nil)

    assert_raise Sphinx.AuthorizationNotPerformedError, fn ->
      send_resp(conn, 200, "Hello, World!")
    end
  end

  test "it shouldn't raise when authorized after ensure_authorization called", %{conn: conn} do
    conn
    |> ensure_authorization([])
    |> put_private(:phoenix_action, :index)
    |> Plug.Adapters.Test.Conn.conn(:get, "/index", nil)
    |> authorize([])
    |> send_resp(200, "All Good")
  end

  test "it shouldn't raise when authorization skipped after ensure_authorization called", %{conn: conn} do
    conn
    |> ensure_authorization([])
    |> put_private(:phoenix_action, :index)
    |> Plug.Adapters.Test.Conn.conn(:get, "/index", nil)
    |> skip_authorization([])
    |> send_resp(200, "All Good")
  end

  test "it shouldn't authorize after skip_authorization called", %{conn: conn} do
    # we take raising request, and skip authorization
    conn
    |> put_private(:phoenix_action, :hurt)
    |> Map.put(:params, %{"id" => 2})
    |> skip_authorization([])
    |> authorize([])
  end

  # Authorization based on :except, :only parameters

  test "it shouldn't authorize if excluded", %{conn: conn} do
    # we take raising request, and skip authorization
    conn
    |> put_private(:phoenix_action, :hurt)
    |> Map.put(:params, %{"id" => 2})
    # try to authorize with different options
    |> authorize(only: :show)
    |> authorize(only: [:show, :index])
    |> authorize(except: :hurt)
    |> authorize(except: [:hurt, :delete])
  end

  test "skip_authorization should accept :except, :only options", %{conn: conn} do
    conn = conn
    |> put_private(:phoenix_action, :hurt)
    |> Map.put(:params, %{"id" => 2})

    assert_raise Sphinx.NotAuthorizedError, fn -> conn |> skip_authorization(only: :show) |> authorize([]) end
    assert_raise Sphinx.NotAuthorizedError, fn -> conn |> skip_authorization(only: [:show, :index]) |> authorize([]) end
    assert_raise Sphinx.NotAuthorizedError, fn -> conn |> skip_authorization(except: :hurt) |> authorize([]) end
    assert_raise Sphinx.NotAuthorizedError, fn -> conn |> skip_authorization(except: [:hurt, :show]) |> authorize([]) end
  end
end
