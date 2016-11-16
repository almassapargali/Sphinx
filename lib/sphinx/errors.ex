defmodule Sphinx.AuthorizationNotPerformedError do
  defexception message: "Authorization hasn't been performed.
    Please either authorize resource, or skip it with :skip_authorization."
end

defmodule Sphinx.NotAuthorizedError do
  defexception plug_status: 403, message: "You do not have access to this resource."
end

defmodule Sphinx.MissingOptionError do
  defexception [:message]
end
