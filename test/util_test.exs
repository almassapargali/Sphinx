defmodule UtilTest do
  use ExUnit.Case

  import Sphinx.Util

  test "should_apply?" do
    conn = %Plug.Conn{private: %{phoenix_action: :index}}

    assert should_apply? conn, []
    assert should_apply? conn, only: :index
    assert should_apply? conn, only: [:index, :show]
    assert should_apply? conn, except: [:delete, :update]

    refute should_apply? conn, only: :delete
    refute should_apply? conn, except: :index
    refute should_apply? conn, except: [:index, :show]
  end

  test "inferring loaded modules" do
    defmodule InferTest.UserController do end
    defmodule InferTest.User do end
    defmodule InferTest.UserAuthorizer do end

    conn = %Plug.Conn{private: %{phoenix_controller: InferTest.UserController}}

    assert infer_module_with_suffix(conn, "") == InferTest.User
    assert infer_module_with_suffix(conn, "Authorizer") == InferTest.UserAuthorizer
    refute infer_module_with_suffix(conn, "Profile")

    # with api namespace
    defmodule InferTest.Api.UserController do end

    conn = %Plug.Conn{private: %{phoenix_controller: InferTest.Api.UserController}}

    assert infer_module_with_suffix(conn, "Authorizer") == InferTest.UserAuthorizer

    # should prefer modules on same namespace
    defmodule InferTest.Api.UserAuthorizer do end

    assert infer_module_with_suffix(conn, "Authorizer") == InferTest.Api.UserAuthorizer
  end
end
