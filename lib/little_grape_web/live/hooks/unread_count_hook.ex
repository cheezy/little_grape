defmodule LittleGrapeWeb.Hooks.UnreadCountHook do
  @moduledoc """
  Shared LiveView hook for the nav unread badge.

  Subscribes the connected LiveView to the current user's PubSub topic and
  keeps the `:unread_count` assign current on `:message_received`,
  `:messages_read`, and `:new_match` events.

  The handle_info hook ALWAYS returns `{:cont, socket}` so LiveViews can layer
  their own behavior on the same events (MatchesLive reloads its match list).
  Every LiveView in the live_session must therefore end its `handle_info`
  clauses with a catch-all `handle_info(_msg, socket)`.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias LittleGrape.Messaging

  def on_mount(:default, _params, _session, socket) do
    # current_scope is set by the UserAuth on_mount that runs before this hook.
    # Never derive the topic from client params.
    user = socket.assigns.current_scope.user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user.id}")
    end

    socket =
      socket
      |> assign(:unread_count, 0)
      |> attach_hook(:unread_count, :handle_info, &handle_unread/2)

    {:cont, socket}
  end

  defp handle_unread({:message_received, _message}, socket), do: refresh(socket)
  defp handle_unread({:messages_read, _payload}, socket), do: refresh(socket)
  defp handle_unread({:new_match, _match}, socket), do: refresh(socket)
  defp handle_unread(_msg, socket), do: {:cont, socket}

  defp refresh(socket) do
    user = socket.assigns.current_scope.user
    {:cont, assign(socket, :unread_count, Messaging.total_unread_count(user))}
  end
end
