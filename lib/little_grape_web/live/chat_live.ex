defmodule LittleGrapeWeb.ChatLive do
  use LittleGrapeWeb, :live_view

  alias LittleGrape.Accounts
  alias LittleGrape.Matches
  alias LittleGrape.Messaging
  alias LittleGrape.Repo

  @impl true
  def mount(%{"match_id" => match_id}, session, socket) do
    socket = assign_current_user(socket, session)

    case socket.assigns[:current_user] do
      nil -> {:ok, redirect(socket, to: ~p"/users/log-in")}
      user -> mount_for_user(socket, user, match_id)
    end
  end

  defp mount_for_user(socket, user, match_id) do
    case authorize_and_load(user, match_id) do
      {:ok, chat_data} ->
        {:ok, setup_chat_socket(socket, user, chat_data)}

      {:error, :not_found} ->
        {:ok, redirect_not_found(socket)}
    end
  end

  defp setup_chat_socket(socket, user, {match, conversation, messages, other_user, other_profile}) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "conversation:#{conversation.id}")
    end

    socket
    |> assign(:user, user)
    |> assign(:match, match)
    |> assign(:conversation, conversation)
    |> assign(:messages, messages)
    |> assign(:other_user, other_user)
    |> assign(:other_profile, other_profile)
    |> assign(:message_form, to_form(%{"content" => ""}))
  end

  defp redirect_not_found(socket) do
    socket
    |> put_flash(:error, "Conversation not found")
    |> redirect(to: ~p"/matches")
  end

  defp authorize_and_load(user, match_id) do
    with match when not is_nil(match) <- Matches.get_match(user, match_id),
         {:ok, conversation} <- Messaging.get_conversation(user, match_id) do
      messages = Messaging.list_messages(conversation)
      {other_user, other_profile} = get_other_participant(match, user.id)
      {:ok, {match, conversation, messages, other_user, other_profile}}
    else
      nil -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
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
           |> assign(:message_form, to_form(%{"content" => ""}))}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    {:noreply,
     socket
     |> assign(:messages, socket.assigns.messages ++ [message])
     |> push_event("scroll_to_bottom", %{})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen max-w-lg mx-auto" id="chat-container" phx-hook="ScrollToBottom">
      <.chat_header other_profile={@other_profile} />

      <div id="messages-container" class="flex-1 overflow-y-auto px-4 py-4 space-y-3 bg-gray-50">
        <%= if @messages == [] do %>
          <.empty_state other_profile={@other_profile} />
        <% else %>
          <%= for message <- @messages do %>
            <.message_bubble message={message} current_user_id={@user.id} />
          <% end %>
        <% end %>
      </div>

      <.message_input form={@message_form} />
    </div>
    """
  end

  defp message_input(assigns) do
    ~H"""
    <div class="px-4 py-3 bg-white border-t">
      <form phx-submit="send_message" class="flex gap-2">
        <input
          type="text"
          name="content"
          value={@form["content"].value}
          placeholder="Type a message..."
          autocomplete="off"
          class="flex-1 px-4 py-2 border border-gray-300 rounded-full focus:outline-none focus:ring-2 focus:ring-pink-500 focus:border-transparent"
        />
        <button
          type="submit"
          class="px-4 py-2 bg-pink-500 text-white rounded-full hover:bg-pink-600 transition-colors"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path d="M10.894 2.553a1 1 0 00-1.788 0l-7 14a1 1 0 001.169 1.409l5-1.429A1 1 0 009 15.571V11a1 1 0 112 0v4.571a1 1 0 00.725.962l5 1.428a1 1 0 001.17-1.408l-7-14z" />
          </svg>
        </button>
      </form>
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
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center h-full text-center">
      <div class="text-5xl mb-4">💬</div>
      <p class="text-gray-500 font-medium">No messages yet</p>
      <p class="text-gray-400 text-sm mt-1">
        Say hello to {display_name(@other_profile)}!
      </p>
    </div>
    """
  end

  defp message_bubble(assigns) do
    is_own = assigns.message.sender_id == assigns.current_user_id

    assigns =
      assigns
      |> assign(:is_own, is_own)
      |> assign(:alignment, if(is_own, do: "justify-end", else: "justify-start"))
      |> assign(
        :bubble_style,
        if(is_own,
          do: "bg-pink-500 text-white rounded-br-sm",
          else: "bg-white text-gray-900 rounded-bl-sm"
        )
      )

    ~H"""
    <div class={"flex #{@alignment}"}>
      <div class={"max-w-xs px-4 py-2 rounded-2xl shadow-sm #{@bubble_style}"}>
        <p class="break-words">{@message.content}</p>
        <p class={[
          "text-xs mt-1",
          if(@is_own, do: "text-pink-200", else: "text-gray-400")
        ]}>
          {format_timestamp(@message.inserted_at)}
        </p>
      </div>
    </div>
    """
  end

  defp display_name(nil), do: "Unknown"
  defp display_name(profile), do: profile.first_name || "Unknown"

  defp format_timestamp(datetime) do
    hour = datetime.hour
    minute = datetime.minute

    {hour_12, am_pm} =
      if hour >= 12,
        do: {rem(hour - 1, 12) + 1, "PM"},
        else: {if(hour == 0, do: 12, else: hour), "AM"}

    "#{hour_12}:#{String.pad_leading(Integer.to_string(minute), 2, "0")} #{am_pm}"
  end
end
