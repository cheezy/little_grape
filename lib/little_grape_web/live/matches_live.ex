defmodule LittleGrapeWeb.MatchesLive do
  use LittleGrapeWeb, :live_view

  alias LittleGrape.Accounts
  alias LittleGrape.Matches
  alias LittleGrape.Messaging

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session)

    case socket.assigns[:current_user] do
      nil ->
        {:ok, redirect(socket, to: ~p"/users/log-in")}

      user ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user.id}")
          send(self(), :load_matches)
        end

        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:loading, true)
         |> assign(:matches, [])
         |> assign(:unread_count, 0)}
    end
  end

  @impl true
  def handle_info(:load_matches, socket) do
    matches = Matches.list_matches_with_details(socket.assigns.user)
    unread_count = Messaging.total_unread_count(socket.assigns.user)

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:matches, matches)
     |> assign(:unread_count, unread_count)}
  end

  @impl true
  def handle_info({:new_match, _match}, socket) do
    matches = Matches.list_matches_with_details(socket.assigns.user)
    unread_count = Messaging.total_unread_count(socket.assigns.user)

    {:noreply,
     socket
     |> assign(:matches, matches)
     |> assign(:unread_count, unread_count)}
  end

  @impl true
  def handle_info({:new_message, _message}, socket) do
    matches = Matches.list_matches_with_details(socket.assigns.user)
    unread_count = Messaging.total_unread_count(socket.assigns.user)

    {:noreply,
     socket
     |> assign(:matches, matches)
     |> assign(:unread_count, unread_count)}
  end

  @impl true
  def handle_info({:messages_read, _payload}, socket) do
    unread_count = Messaging.total_unread_count(socket.assigns.user)
    {:noreply, assign(socket, :unread_count, unread_count)}
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
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold text-center mb-8">Matches</h1>

      <%= if @loading do %>
        <.loading_spinner />
      <% else %>
        <%= if @matches == [] do %>
          <.empty_state />
        <% else %>
          <div class="space-y-3">
            <%= for match_data <- @matches do %>
              <.match_card match_data={match_data} />
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp loading_spinner(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-20">
      <div class="w-12 h-12 border-4 border-pink-200 border-t-pink-500 rounded-full animate-spin">
      </div>
      <p class="text-gray-500 mt-4">Loading your matches...</p>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <div class="text-6xl mb-4">💝</div>
      <p class="text-gray-500 text-lg font-medium">No matches yet</p>
      <p class="text-gray-400 mt-2">Keep swiping to find your perfect match!</p>
      <.link
        navigate={~p"/discover"}
        class="inline-block mt-6 bg-pink-500 hover:bg-pink-600 text-white font-semibold py-3 px-6 rounded-full transition-colors"
      >
        Start Discovering
      </.link>
    </div>
    """
  end

  defp match_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/chat/#{@match_data.match.id}"}
      class={[
        "flex items-center gap-4 p-4 rounded-xl shadow-md hover:shadow-lg transition-shadow",
        if(@match_data.is_new_match, do: "bg-pink-50 border-2 border-pink-200", else: "bg-white")
      ]}
    >
      <div class="relative">
        <%= if @match_data.other_profile && @match_data.other_profile.profile_picture do %>
          <img
            src={@match_data.other_profile.profile_picture}
            alt={"#{@match_data.other_profile.first_name}'s photo"}
            class="w-16 h-16 rounded-full object-cover"
          />
        <% else %>
          <div class="w-16 h-16 rounded-full bg-gray-200 flex items-center justify-center">
            <span class="text-gray-400 text-2xl">👤</span>
          </div>
        <% end %>
        <%= if @match_data.unread_count > 0 do %>
          <span class="absolute -top-1 -right-1 bg-pink-500 text-white text-xs font-bold rounded-full h-5 min-w-5 px-1 flex items-center justify-center">
            {@match_data.unread_count}
          </span>
        <% end %>
      </div>

      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <h3 class="font-semibold text-gray-900 truncate">
            {display_name(@match_data.other_profile)}
          </h3>
          <%= if @match_data.is_new_match do %>
            <span class="text-xs font-semibold text-pink-500 bg-pink-100 px-2 py-0.5 rounded-full whitespace-nowrap">
              NEW MATCH
            </span>
          <% end %>
        </div>
        <p class={[
          "text-sm truncate",
          if(@match_data.unread_count > 0, do: "text-gray-900 font-medium", else: "text-gray-500")
        ]}>
          {message_preview(@match_data.last_message)}
        </p>
      </div>

      <div class="text-gray-400">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-5 w-5"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path
            fill-rule="evenodd"
            d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
            clip-rule="evenodd"
          />
        </svg>
      </div>
    </.link>
    """
  end

  defp display_name(nil), do: "Unknown"
  defp display_name(profile), do: profile.first_name || "Unknown"

  defp message_preview(nil), do: "Start a conversation!"
  defp message_preview(message), do: truncate_message(message.content)

  defp truncate_message(content) when byte_size(content) > 50 do
    String.slice(content, 0, 47) <> "..."
  end

  defp truncate_message(content), do: content
end
