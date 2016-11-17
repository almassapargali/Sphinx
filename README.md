# Sphinx

An authorization libriary for Phoenix application inspired by [CanCan](https://github.com/CanCanCommunity/cancancan),
[Canary](https://github.com/cpjk/canary), and others. It follows Convention over Configuration design, yet allowing full customizations.

[Read the docs](http://hexdocs.pm/sphinx)

## Installation

  0. Add `sphinx` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:sphinx, "~> 0.1.0"}]
    end
    ```

  Then run `mix deps.get` to fetch the dependencies.

  1. Configure `:repo` in your `config.exs`:

    ```elixir
    config :sphinx, :repo, MyApp.Repo
    ```

## Usage

Say you want to authorize your `PostController`:

  0. Create `web/authorizers/post_authorizer.ex` and define `authorize?` functions for each action in controller like:

    ```elixir
    defmodule MyApp.PostAuthorizer do
      def authorize?(_, :index, Post), do: true

      def authorize?(_, :show, %Post{}), do: true

      def authorize?(%User{}, :create, Post), do: true

      def authorize?(%User{id: id}, action, %Post{author_id: id}) when action in [:update, :delete], do: true

      def authorize?(_, _, _), do: false
    end
    ```

  1. Call `plug :authorize` inside your `PostController`. You may want to `import Sphinx.Plugs` in your `web.ex`
    for controller scope.

  2. You can now access post in your controller actions like: `conn.assigns.resource` if authorization passes,
    and user gets 403 view if it fails.

  3. Profit!

  See [plug docs](https://hexdocs.pm/sphinx/Sphinx.Plugs.html#authorize/2) for more options.

## Ensuring authorization

If you want to make sure all your requests are authorized, add this in your pipelines:

```elixir
import Sphinx.Plugx

plug :ensure_authorization
```

Now, if any your requests is about to return without going through authorization, Sphinx would rise `Sphinx.AuthorizationNotPerformedError`.
You can skip authorization for some of your actions in controller like:

```elixir
plug :skip_authorization, only: [:index, :show]
```

## License

MIT License, Copyright (c) 2016 Almas Sapargali
