defmodule Sphinx.Util do
  @moduledoc false

  def should_apply?(%Plug.Conn{private: %{phoenix_action: action}}, opts) do
    case {opts[:only], opts[:except]} do
      {nil, nil} -> true
      {only, nil} -> action_listed?(only, action)
      {nil, except} -> !action_listed?(except, action)
      _ -> false
    end
  end

  defp action_listed?(list, action) when is_list(list), do: action in list
  defp action_listed?(list, action) when is_atom(list), do: action == list

  # infer loaded module from conn's controller by replacing Controller suffix with given suffix
  def infer_module_with_suffix(%Plug.Conn{private: %{phoenix_controller: controller}}, suffix) do
    possible_module = controller |> to_string() |> String.replace_suffix("Controller", suffix)

    # try also by removing .Api. namespace
    [possible_module, String.replace(possible_module, ".Api.", ".")]
    |> Enum.map(&String.to_atom/1)
    |> Enum.find(&Code.ensure_loaded?/1)
  end
end
