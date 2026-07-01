defmodule LittleGrapeWeb.ChatLive do
  use LittleGrapeWeb, :live_view

  import LittleGrapeWeb.ChatComponents,
    only: [messages_list: 1, message_input: 1]

  alias LittleGrape.Accounts
  alias LittleGrape.Matches
  alias LittleGrape.Messaging
  alias LittleGrape.Repo

  @impl true
  def mount(%{"match_id" => match_id}, session, socket) do
    socket = assign_current_user(socket, session)

    case socket.assigns[:current_user] do
      nil ->
        {:ok, redirect(socket, to: ~p"/users/log-in")}

      user ->
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
             |> assign(:show_profile, false)
             |> assign(:unread_count, 0)}
        end
    end
  end

  defp redirect_not_found(socket) do
    socket
    |> put_flash(:error, gettext("Conversation not found"))
    |> redirect(to: ~p"/matches")
  end

  defp get_other_participant(match, user_id) do
    other_user =
      if match.user_a_id == user_id do
        Repo.preload(match, :user_b).user_b
      else
        Repo.preload(match, :user_a).user_a
      end

    other_profile = Repo.preload(other_user, :profile).profile
    {other_user, other_profile}
  end

  defp assign_current_user(socket, session) do
    case session["user_token"] do
      nil ->
        assign(socket, :current_user, nil)

      token ->
        case Accounts.get_user_by_session_token(token) do
          {user, _token_inserted_at} -> assign(socket, :current_user, user)
          nil -> assign(socket, :current_user, nil)
        end
    end
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) do
    content = String.trim(content)

    if content == "" do
      {:noreply, socket}
    else
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
  def handle_info({:message_received, _message}, socket) do
    unread_count = Messaging.total_unread_count(socket.assigns.user)
    {:noreply, assign(socket, :unread_count, unread_count)}
  end

  @impl true
  def handle_info({:messages_read, _payload}, socket) do
    unread_count = Messaging.total_unread_count(socket.assigns.user)
    {:noreply, assign(socket, :unread_count, unread_count)}
  end

  @impl true
  def handle_info({:new_match, _match}, socket) do
    # Just update unread count for nav badge
    unread_count = Messaging.total_unread_count(socket.assigns.user)
    {:noreply, assign(socket, :unread_count, unread_count)}
  end

  @impl true
  def handle_info({:load_conversation, match_id, match}, socket) do
    user = socket.assigns.user

    case Messaging.get_conversation(user, match_id) do
      {:ok, conversation} ->
        messages = Messaging.list_messages(conversation)
        {other_user, other_profile} = get_other_participant(match, user.id)

        Phoenix.PubSub.subscribe(LittleGrape.PubSub, "conversation:#{conversation.id}")
        Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user.id}")
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

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @loading do %>
      <div class="flex flex-col h-screen max-w-lg mx-auto">
        <.loading_header />
        <.loading_spinner />
      </div>
    <% else %>
      <div
        class="flex flex-col h-screen max-w-lg mx-auto"
        id="chat-container"
        phx-hook="ScrollToBottom"
      >
        <.chat_header other_profile={@other_profile} />

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

  defp loading_header(assigns) do
    ~H"""
    <div class="flex items-center gap-3 px-4 py-3 bg-white border-b shadow-sm">
      <.link navigate={~p"/matches"} class="text-gray-500 hover:text-gray-700">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-6 w-6"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
        </svg>
      </.link>
      <div class="flex items-center gap-3 flex-1">
        <div class="w-10 h-10 rounded-full bg-gray-200 animate-pulse"></div>
        <div class="h-4 w-24 bg-gray-200 rounded animate-pulse"></div>
      </div>
    </div>
    """
  end

  defp loading_spinner(assigns) do
    ~H"""
    <div class="flex-1 flex flex-col items-center justify-center bg-gray-50">
      <div class="w-12 h-12 border-4 border-red-200 border-t-red-500 rounded-full animate-spin"></div>
      <p class="text-gray-500 mt-4">{gettext("Loading messages...")}</p>
    </div>
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
              <span class="text-gray-400 text-5xl">👤</span>
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
          Close
        </button>
      </div>
    </div>
    """
  end

  defp chat_header(assigns) do
    ~H"""
    <div class="flex items-center gap-3 px-4 py-3 bg-white border-b shadow-sm">
      <.link navigate={~p"/matches"} class="text-gray-500 hover:text-gray-700">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-6 w-6"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
        </svg>
      </.link>
      <button phx-click="show_profile" class="flex items-center gap-3 flex-1 text-left">
        <%= if @other_profile && @other_profile.profile_picture do %>
          <img
            src={@other_profile.profile_picture}
            alt={"#{@other_profile.first_name}'s photo"}
            class="w-10 h-10 rounded-full object-cover"
          />
        <% else %>
          <div class="w-10 h-10 rounded-full bg-gray-200 flex items-center justify-center">
            <span class="text-gray-400 text-lg">👤</span>
          </div>
        <% end %>
        <h1 class="font-semibold text-gray-900">{display_name(@other_profile)}</h1>
      </button>
    </div>
    """
  end

  defp display_name(nil), do: "Unknown"
  defp display_name(profile), do: profile.first_name || "Unknown"
end
