defmodule LittleGrapeWeb.ChatLive do
  use LittleGrapeWeb, :live_view

  import LittleGrapeWeb.ChatComponents,
    only: [chat_header: 1, display_name: 1, messages_list: 1, message_input: 1]

  alias LittleGrape.Matches
  alias LittleGrape.Messaging
  alias LittleGrapeWeb.MessageSending

  @impl true
  def mount(%{"match_id" => match_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    # Check authorization synchronously to return proper redirect
    case Matches.get_match(user, match_id) do
      nil ->
        {:ok, redirect_not_found(socket)}

      match ->
        if connected?(socket) do
          send(self(), {:load_conversation, match_id, match})
        end

        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:match_id, match_id)
         |> assign(:loading, true)
         |> assign(:match, nil)
         |> assign(:conversation, nil)
         |> assign(:messages, [])
         |> assign(:other_user, nil)
         |> assign(:other_profile, nil)
         |> assign(:message_form, to_form(%{"content" => ""}))
         |> assign(:show_profile, false)}
    end
  end

  defp redirect_not_found(socket) do
    socket
    |> put_flash(:error, gettext("Conversation not found"))
    |> redirect(to: ~p"/matches")
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) do
    MessageSending.send_message(socket, content)
  end

  @impl true
  def handle_event("show_profile", _params, socket) do
    {:noreply, assign(socket, :show_profile, true)}
  end

  @impl true
  def handle_event("close_profile", _params, socket) do
    {:noreply, assign(socket, :show_profile, false)}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    # If message is from other user in this conversation, mark as read immediately
    # since we're viewing the conversation
    if message.conversation_id == socket.assigns.conversation.id and
         message.sender_id != socket.assigns.user.id do
      Messaging.mark_as_read(socket.assigns.user, socket.assigns.conversation.id)
    end

    unread_count = Messaging.total_unread_count(socket.assigns.user)

    {:noreply,
     socket
     |> assign(:messages, socket.assigns.messages ++ [message])
     |> assign(:unread_count, unread_count)
     |> push_event("scroll_to_bottom", %{})}
  end

  @impl true
  def handle_info({:load_conversation, match_id, match}, socket) do
    user = socket.assigns.user

    case Messaging.get_conversation(user, match_id) do
      {:ok, conversation} ->
        messages = Messaging.list_messages(conversation)
        {other_user, other_profile} = Matches.other_participant(match, user.id)

        Phoenix.PubSub.subscribe(LittleGrape.PubSub, "conversation:#{conversation.id}")
        Messaging.mark_as_read(user, conversation.id)
        unread_count = Messaging.total_unread_count(user)

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:match, match)
         |> assign(:conversation, conversation)
         |> assign(:messages, messages)
         |> assign(:other_user, other_user)
         |> assign(:other_profile, other_profile)
         |> assign(:unread_count, unread_count)}

      {:error, :not_found} ->
        {:noreply, redirect_not_found(socket)}
    end
  end

  # Unread-badge events (:message_received, :messages_read, :new_match) are
  # handled by UnreadCountHook, which conts so duplicate deliveries land here.
  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @loading do %>
      <div class="flex flex-col h-screen max-w-lg mx-auto">
        <.chat_header navigate_back={~p"/matches"} loading />
        <.loading_spinner
          message={gettext("Loading messages...")}
          class="flex-1 flex flex-col items-center justify-center bg-gray-50"
        />
      </div>
    <% else %>
      <div
        class="flex flex-col h-screen max-w-lg mx-auto"
        id="chat-container"
        phx-hook="ScrollToBottom"
      >
        <.chat_header
          other_profile={@other_profile}
          navigate_back={~p"/matches"}
          on_profile_click="show_profile"
        />

        <.messages_list
          messages={@messages}
          other_profile={@other_profile}
          current_user_id={@user.id}
        />

        <.message_input form={@message_form} />

        <%= if @show_profile do %>
          <.profile_modal other_profile={@other_profile} />
        <% end %>
      </div>
    <% end %>
    """
  end

  defp profile_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
      phx-click="close_profile"
    >
      <div
        class="bg-white rounded-2xl p-6 max-w-sm w-full mx-4 shadow-xl"
        phx-click-away="close_profile"
      >
        <div class="text-center">
          <%= if @other_profile && @other_profile.profile_picture do %>
            <img
              src={@other_profile.profile_picture}
              alt={"#{@other_profile.first_name}'s photo"}
              class="w-32 h-32 rounded-full object-cover mx-auto mb-4"
            />
          <% else %>
            <div class="w-32 h-32 rounded-full bg-gray-200 flex items-center justify-center mx-auto mb-4">
              <span class="text-gray-400 text-5xl" aria-hidden="true">👤</span>
            </div>
          <% end %>
          <h2 class="text-2xl font-bold text-gray-900 mb-2">{display_name(@other_profile)}</h2>
          <%= if @other_profile && @other_profile.bio do %>
            <p class="text-gray-600">{@other_profile.bio}</p>
          <% end %>
        </div>
        <button
          phx-click="close_profile"
          class="mt-6 w-full py-2 bg-gray-100 text-gray-700 rounded-full hover:bg-gray-200 transition-colors"
        >
          {gettext("Close")}
        </button>
      </div>
    </div>
    """
  end
end
