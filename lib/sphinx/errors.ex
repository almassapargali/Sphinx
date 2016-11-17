defmodule Sphinx.AuthorizationNotPerformedError do
  @moduledoc """
  Raised when using `ensure_authorization` without calling `authorize`.
  """
  defexception message: "Authorization hasn't been performed.
    Please either authorize resource, or skip it with :skip_authorization."
end

defmodule Sphinx.NotAuthorizedError do
  @moduledoc """
  Raised when authorization fails.

  By default, message says: "You do not have access to this resource.". To customize it, fail in your authorizer with:
  `{false, "reason"}`.
  """
  defexception plug_status: 403, message: "You do not have access to this resource."
end

defmodule Sphinx.MissingOptionError do
  defexception [:message]
end
