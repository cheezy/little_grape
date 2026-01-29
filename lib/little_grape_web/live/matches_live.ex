defmodule LittleGrapeWeb.MatchesLive do
  use LittleGrapeWeb, :live_view

  alias LittleGrape.Accounts
  alias LittleGrape.Matches

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session)

    case socket.assigns[:current_user] do
      nil ->
        {:ok, redirect(socket, to: ~p"/users/log-in")}

      user ->
        matches = Matches.list_matches_with_details(user)

        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:matches, matches)}
    end
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

      <%= if @matches == [] do %>
        <.empty_state />
      <% else %>
        <div class="space-y-3">
          <%= for match_data <- @matches do %>
            <.match_card match_data={match_data} />
          <% end %>
        </div>
      <% end %>
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
      class="flex items-center gap-4 p-4 bg-white rounded-xl shadow-md hover:shadow-lg transition-shadow"
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
      </div>

      <div class="flex-1 min-w-0">
        <h3 class="font-semibold text-gray-900 truncate">
          {display_name(@match_data.other_profile)}
        </h3>
        <p class="text-gray-500 text-sm truncate">
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
