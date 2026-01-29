defmodule LittleGrape.TestLogFilter do
  @moduledoc """
  Logger filter to suppress expected Postgrex disconnection errors in tests.

  These errors occur when test processes exit while database connections are still
  active, which is expected behavior with async LiveView tests.
  """

  @doc """
  Filters out Postgrex disconnection errors caused by client process exits.

  Returns :stop to suppress the log entry, :ignore to pass it through.
  """
  def filter_postgrex_disconnected(log_event, _opts) do
    case log_event do
      %{msg: {:string, msg}} when is_list(msg) ->
        filter_message(List.to_string(msg))

      %{msg: {:string, msg}} when is_binary(msg) ->
        filter_message(msg)

      %{msg: {format, args}} when is_list(format) ->
        filter_message(:io_lib.format(format, args) |> List.to_string())

      _ ->
        :ignore
    end
  rescue
    _ -> :ignore
  end

  defp filter_message(msg) do
    if String.contains?(msg, "DBConnection.ConnectionError") and
         String.contains?(msg, "exited") do
      :stop
    else
      :ignore
    end
  end
end
