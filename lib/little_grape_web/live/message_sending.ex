defmodule LittleGrapeWeb.MessageSending do
  @moduledoc """
  Shared `"send_message"` event logic for ChatLive and MatchesLive.
  """
  use Gettext, backend: LittleGrapeWeb.Gettext

  import Phoenix.Component, only: [assign: 3, to_form: 1]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias LittleGrape.Messaging

  @doc """
  Trims and sends `content` to `socket.assigns.conversation`.

  No-op when content is blank or no conversation is selected/loaded yet
  (`conversation` is nil). Returns `{:noreply, socket}`.
  """
  def send_message(socket, content) do
    content = String.trim(content)

    cond do
      content == "" ->
        {:noreply, socket}

      is_nil(socket.assigns.conversation) ->
        {:noreply, socket}

      true ->
        case Messaging.send_message(socket.assigns.user, socket.assigns.conversation.id, content) do
          {:ok, _message} ->
            {:noreply,
             socket
             |> assign(:message_form, to_form(%{"content" => ""}))
             |> push_event("clear:chat-message-input", %{})}

          {:error, _changeset} ->
            {:noreply,
             put_flash(socket, :error, gettext("Failed to send message. Please try again."))}
        end
    end
  end
end
