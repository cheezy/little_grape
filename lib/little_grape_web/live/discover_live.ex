defmodule LittleGrapeWeb.DiscoverLive do
  use LittleGrapeWeb, :live_view

  alias LittleGrape.Accounts
  alias LittleGrape.Discovery
  alias LittleGrape.Matches
  alias LittleGrape.Messaging
  alias LittleGrape.Repo
  alias LittleGrape.Swipes

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session)

    case socket.assigns[:current_user] do
      nil ->
        {:ok, redirect(socket, to: ~p"/users/log-in")}

      user ->
        user = Repo.preload(user, :profile)

        if Accounts.profile_complete?(user.profile) do
          if connected?(socket) do
            Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user.id}")
            send(self(), :load_candidates)
          end

          {:ok,
           socket
           |> assign(:user, user)
           |> assign(:loading, true)
           |> assign(:candidates, [])
           |> assign(:current_candidate, nil)
           |> assign(:swiping, false)
           |> assign(:show_match_modal, false)
           |> assign(:matched_profile, nil)
           |> assign(:expanded, false)
           |> assign(:unread_count, 0)}
        else
          missing = Accounts.missing_profile_fields(user.profile)

          message =
            "Please complete your profile to start discovering matches. Missing: #{Enum.join(missing, ", ")}"

          {:ok,
           socket
           |> put_flash(:error, message)
           |> redirect(to: ~p"/users/profile")}
        end
    end
  end

  @impl true
  def handle_event("swipe", %{"action" => action}, socket) do
    if socket.assigns.swiping or is_nil(socket.assigns.current_candidate) do
      {:noreply, socket}
    else
      socket = assign(socket, :swiping, true)
      user = socket.assigns.user
      candidate = socket.assigns.current_candidate

      case Swipes.create_swipe(user, candidate.user_id, action) do
        {:ok, _swipe} ->
          socket = handle_swipe_success(socket, action, user.id, candidate)
          {:noreply, socket}

        {:error, _changeset} ->
          # Swipe already exists or other error - show feedback and advance
          socket =
            socket
            |> put_flash(:error, "Something went wrong. Please try again.")
            |> advance_to_next_candidate()

          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("close_match_modal", _params, socket) do
    {:noreply, assign(socket, :show_match_modal, false)}
  end

  @impl true
  def handle_event("toggle_expanded", _params, socket) do
    {:noreply, assign(socket, :expanded, !socket.assigns.expanded)}
  end

  @impl true
  def handle_info({:new_message, _message}, socket) do
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
    # Just update unread count, don't need to do anything else for discovery
    unread_count = Messaging.total_unread_count(socket.assigns.user)
    {:noreply, assign(socket, :unread_count, unread_count)}
  end

  @impl true
  def handle_info(:load_candidates, socket) do
    candidates = Discovery.get_candidates(socket.assigns.user)
    current_candidate = List.first(candidates)
    unread_count = Messaging.total_unread_count(socket.assigns.user)

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:candidates, candidates)
     |> assign(:current_candidate, current_candidate)
     |> assign(:unread_count, unread_count)}
  end

  defp handle_swipe_success(socket, action, user_id, candidate) do
    if action == "like" and Swipes.check_for_match(user_id, candidate.user_id) do
      # It's a match! Create the match record
      case Matches.create_match(user_id, candidate.user_id) do
        {:ok, _result} ->
          socket
          |> assign(:matched_profile, candidate)
          |> assign(:show_match_modal, true)
          |> advance_to_next_candidate()

        {:error, _reason} ->
          socket
          |> put_flash(:error, "Something went wrong creating the match. Please try again.")
          |> advance_to_next_candidate()
      end
    else
      advance_to_next_candidate(socket)
    end
  end

  defp advance_to_next_candidate(socket) do
    remaining = Enum.drop(socket.assigns.candidates, 1)

    socket
    |> assign(:candidates, remaining)
    |> assign(:current_candidate, List.first(remaining))
    |> assign(:swiping, false)
    |> assign(:expanded, false)
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

  defp calculate_age(nil), do: nil

  defp calculate_age(birthdate) do
    today = Date.utc_today()
    years = today.year - birthdate.year

    birthday_this_year = Date.new!(today.year, birthdate.month, birthdate.day)

    case Date.compare(birthday_this_year, today) do
      :gt -> years - 1
      _ -> years
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold text-center mb-8">Discover</h1>

      <%= if @loading do %>
        <.loading_spinner />
      <% else %>
        <%= if @current_candidate do %>
          <.profile_card profile={@current_candidate} swiping={@swiping} expanded={@expanded} />
        <% else %>
          <div class="text-center py-12">
            <div class="text-6xl mb-4">🔍</div>
            <p class="text-gray-500 text-lg font-medium">No more profiles right now</p>
            <p class="text-gray-400 mt-2">Try broadening your preferences to see more people!</p>
            <.link
              navigate={~p"/users/profile"}
              class="inline-block mt-6 bg-pink-500 hover:bg-pink-600 text-white font-semibold py-3 px-6 rounded-full transition-colors"
            >
              Update Preferences
            </.link>
          </div>
        <% end %>
      <% end %>

      <%= if @show_match_modal do %>
        <.match_modal profile={@matched_profile} />
      <% end %>
    </div>
    """
  end

  defp loading_spinner(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-20">
      <div class="w-12 h-12 border-4 border-pink-200 border-t-pink-500 rounded-full animate-spin">
      </div>
      <p class="text-gray-500 mt-4">Finding people near you...</p>
    </div>
    """
  end

  defp profile_card(assigns) do
    assigns = assign(assigns, :age, calculate_age(assigns.profile.birthdate))

    ~H"""
    <div class="bg-white rounded-2xl shadow-xl overflow-hidden">
      <div
        class={[
          "relative cursor-pointer transition-all",
          if(@expanded, do: "aspect-[3/5]", else: "aspect-[3/4]")
        ]}
        phx-click="toggle_expanded"
      >
        <%= if @profile.profile_picture do %>
          <img
            src={@profile.profile_picture}
            alt={"#{@profile.first_name}'s photo"}
            class="w-full h-full object-cover"
          />
        <% else %>
          <div class="w-full h-full bg-gray-200 flex items-center justify-center">
            <span class="text-gray-400 text-6xl">👤</span>
          </div>
        <% end %>

        <div class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/70 to-transparent p-6">
          <h2 class="text-white text-2xl font-bold">
            {@profile.first_name}
            <%= if @age do %>
              , {@age}
            <% end %>
          </h2>
          <%= if @profile.city || @profile.country do %>
            <p class="text-white/80 text-lg">
              {[@profile.city, @profile.country] |> Enum.filter(& &1) |> Enum.join(", ")}
            </p>
          <% end %>
          <%= unless @expanded do %>
            <p class="text-white/60 text-sm mt-2">Tap to see more</p>
          <% end %>
        </div>
      </div>

      <%= if @expanded do %>
        <.expanded_profile_details profile={@profile} />
      <% end %>

      <div class="flex justify-center gap-8 py-6">
        <button
          phx-click="swipe"
          phx-value-action="pass"
          disabled={@swiping}
          class="w-16 h-16 rounded-full bg-gray-100 hover:bg-gray-200 flex items-center justify-center text-3xl shadow-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed"
        >
          ✕
        </button>
        <button
          phx-click="swipe"
          phx-value-action="like"
          disabled={@swiping}
          class="w-16 h-16 rounded-full bg-pink-500 hover:bg-pink-600 flex items-center justify-center text-3xl text-white shadow-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed"
        >
          ♥
        </button>
      </div>
    </div>
    """
  end

  defp expanded_profile_details(assigns) do
    ~H"""
    <div class="p-6 space-y-4 border-t border-gray-100 max-h-96 overflow-y-auto">
      <%= if @profile.bio do %>
        <div>
          <h3 class="font-semibold text-gray-700 mb-1">About Me</h3>
          <p class="text-gray-600">{@profile.bio}</p>
        </div>
      <% end %>

      <%= if @profile.interests && @profile.interests != [] do %>
        <div>
          <h3 class="font-semibold text-gray-700 mb-2">Interests</h3>
          <div class="flex flex-wrap gap-2">
            <%= for interest <- @profile.interests do %>
              <span class="px-3 py-1 bg-pink-100 text-pink-700 rounded-full text-sm">
                {format_value(interest)}
              </span>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @profile.occupation do %>
        <div>
          <h3 class="font-semibold text-gray-700 mb-1">Occupation</h3>
          <p class="text-gray-600">{@profile.occupation}</p>
        </div>
      <% end %>

      <%= if @profile.looking_for do %>
        <div>
          <h3 class="font-semibold text-gray-700 mb-1">Looking For</h3>
          <p class="text-gray-600">{format_value(@profile.looking_for)}</p>
        </div>
      <% end %>

      <div class="grid grid-cols-2 gap-4">
        <%= if @profile.height_cm do %>
          <div>
            <h3 class="font-semibold text-gray-700 mb-1">Height</h3>
            <p class="text-gray-600">{@profile.height_cm} cm</p>
          </div>
        <% end %>

        <%= if @profile.body_type do %>
          <div>
            <h3 class="font-semibold text-gray-700 mb-1">Body Type</h3>
            <p class="text-gray-600">{format_value(@profile.body_type)}</p>
          </div>
        <% end %>

        <%= if @profile.education do %>
          <div>
            <h3 class="font-semibold text-gray-700 mb-1">Education</h3>
            <p class="text-gray-600">{format_value(@profile.education)}</p>
          </div>
        <% end %>

        <%= if @profile.religion do %>
          <div>
            <h3 class="font-semibold text-gray-700 mb-1">Religion</h3>
            <p class="text-gray-600">{format_value(@profile.religion)}</p>
          </div>
        <% end %>

        <%= if @profile.smoking do %>
          <div>
            <h3 class="font-semibold text-gray-700 mb-1">Smoking</h3>
            <p class="text-gray-600">{format_value(@profile.smoking)}</p>
          </div>
        <% end %>

        <%= if @profile.drinking do %>
          <div>
            <h3 class="font-semibold text-gray-700 mb-1">Drinking</h3>
            <p class="text-gray-600">{format_value(@profile.drinking)}</p>
          </div>
        <% end %>
      </div>

      <%= if @profile.languages && @profile.languages != [] do %>
        <div>
          <h3 class="font-semibold text-gray-700 mb-1">Languages</h3>
          <p class="text-gray-600">
            {Enum.map(@profile.languages, &format_language/1) |> Enum.join(", ")}
          </p>
        </div>
      <% end %>

      <p class="text-center text-gray-400 text-sm pt-2">Tap photo to collapse</p>
    </div>
    """
  end

  defp format_value(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_language("sq"), do: "Albanian"
  defp format_language("en"), do: "English"
  defp format_language("it"), do: "Italian"
  defp format_language("de"), do: "German"
  defp format_language("fr"), do: "French"
  defp format_language("sr"), do: "Serbian"
  defp format_language("mk"), do: "Macedonian"
  defp format_language("tr"), do: "Turkish"
  defp format_language("other"), do: "Other"
  defp format_language(code), do: code

  defp match_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div class="bg-white rounded-2xl p-8 max-w-sm mx-4 text-center shadow-2xl">
        <h2 class="text-3xl font-bold text-pink-500 mb-4">It's a Match!</h2>

        <div class="mb-6">
          <%= if @profile.profile_picture do %>
            <img
              src={@profile.profile_picture}
              alt={"#{@profile.first_name}'s photo"}
              class="w-32 h-32 rounded-full object-cover mx-auto border-4 border-pink-500"
            />
          <% else %>
            <div class="w-32 h-32 rounded-full bg-gray-200 mx-auto flex items-center justify-center border-4 border-pink-500">
              <span class="text-gray-400 text-4xl">👤</span>
            </div>
          <% end %>
        </div>

        <p class="text-gray-600 mb-6">
          You and {@profile.first_name} liked each other!
        </p>

        <button
          phx-click="close_match_modal"
          class="w-full bg-pink-500 hover:bg-pink-600 text-white font-semibold py-3 px-6 rounded-full transition-colors"
        >
          Keep Swiping
        </button>
      </div>
    </div>
    """
  end
end
