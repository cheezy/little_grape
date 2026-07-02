defmodule LittleGrapeWeb.MatchesLive do
  use LittleGrapeWeb, :live_view

  import LittleGrapeWeb.ChatComponents,
    only: [chat_header: 1, display_name: 1, messages_list: 1, message_input: 1]

  alias LittleGrape.Discovery
  alias LittleGrape.Matches
  alias LittleGrape.Messaging
  alias LittleGrape.Repo
  alias LittleGrapeWeb.MessageSending

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if connected?(socket) do
      send(self(), :load_matches)
    end

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:loading, true)
     |> assign(:matches, [])
     |> assign(:ai_match, nil)
     |> assign_no_selection()}
  end

  defp assign_no_selection(socket) do
    socket
    |> assign(:selected_match_id, nil)
    |> assign(:selected_match, nil)
    |> assign(:conversation, nil)
    |> assign(:messages, [])
    |> assign(:other_profile, nil)
    |> assign(:message_form, to_form(%{"content" => ""}))
    |> assign(:current_topic, nil)
  end

  @impl true
  def handle_info(:load_matches, socket) do
    user = socket.assigns.user
    matches = Matches.list_matches_with_details(user)
    unread_count = Messaging.total_unread_count(user)
    ai_match = compute_ai_match(user)

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:matches, matches)
     |> assign(:ai_match, ai_match)
     |> assign(:unread_count, unread_count)}
  end

  # :unread_count is maintained by UnreadCountHook before these clauses run;
  # they only handle the MatchesLive-specific list reload.
  @impl true
  def handle_info({:new_match, _match}, socket) do
    matches = Matches.list_matches_with_details(socket.assigns.user)
    {:noreply, assign(socket, :matches, matches)}
  end

  @impl true
  def handle_info({:message_received, _message}, socket) do
    matches = Matches.list_matches_with_details(socket.assigns.user)
    {:noreply, assign(socket, :matches, matches)}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    if socket.assigns.conversation && message.conversation_id == socket.assigns.conversation.id do
      if message.sender_id != socket.assigns.user.id do
        Messaging.mark_as_read(socket.assigns.user, socket.assigns.conversation.id)
      end

      unread_count = Messaging.total_unread_count(socket.assigns.user)

      {:noreply,
       socket
       |> assign(:messages, socket.assigns.messages ++ [message])
       |> assign(:unread_count, unread_count)
       |> push_event("scroll_to_bottom", %{})}
    else
      {:noreply, socket}
    end
  end

  # Unread-badge events not matched above (e.g. :messages_read) are handled by
  # UnreadCountHook, which conts so duplicate deliveries land here.
  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select_match", %{"match-id" => match_id_str}, socket) do
    user = socket.assigns.user

    with {match_id, ""} when match_id in 1..9_223_372_036_854_775_807 <-
           Integer.parse(match_id_str),
         %Matches.Match{} = match <- Matches.get_match(user, match_id) do
      {:noreply, select_match(socket, match, user)}
    else
      # Malformed client param or unknown match — never crash the LiveView
      _error ->
        {:noreply, put_flash(socket, :error, gettext("Conversation not found."))}
    end
  end

  @impl true
  def handle_event("close_chat", _params, socket) do
    {:noreply,
     socket
     |> unsubscribe_from_current_topic()
     |> assign_no_selection()}
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) do
    MessageSending.send_message(socket, content)
  end

  defp compute_ai_match(user) do
    user =
      if Ecto.assoc_loaded?(user.profile),
        do: user,
        else: Repo.preload(user, :profile)

    case Discovery.ai_pick(user) do
      nil -> nil
      {profile, _score, reasons} -> %{profile: profile, reasons: reasons}
    end
  end

  defp select_match(socket, match, user) do
    case Messaging.get_conversation(user, match.id) do
      {:ok, conversation} ->
        do_select_match(socket, match, user, conversation)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, gettext("Conversation not found."))
        |> assign_no_selection()
    end
  end

  defp do_select_match(socket, match, user, conversation) do
    messages = Messaging.list_messages(conversation)
    {_other_user, other_profile} = Matches.other_participant(match, user.id)

    socket = unsubscribe_from_current_topic(socket)
    new_topic = "conversation:#{conversation.id}"
    Phoenix.PubSub.subscribe(LittleGrape.PubSub, new_topic)

    Messaging.mark_as_read(user, conversation.id)
    unread_count = Messaging.total_unread_count(user)
    matches = Matches.list_matches_with_details(user)

    socket
    |> assign(:selected_match_id, match.id)
    |> assign(:selected_match, match)
    |> assign(:conversation, conversation)
    |> assign(:messages, messages)
    |> assign(:other_profile, other_profile)
    |> assign(:message_form, to_form(%{"content" => ""}))
    |> assign(:current_topic, new_topic)
    |> assign(:matches, matches)
    |> assign(:unread_count, unread_count)
    |> push_event("scroll_to_bottom", %{})
  end

  defp unsubscribe_from_current_topic(%{assigns: %{current_topic: nil}} = socket), do: socket

  defp unsubscribe_from_current_topic(%{assigns: %{current_topic: topic}} = socket) do
    Phoenix.PubSub.unsubscribe(LittleGrape.PubSub, topic)
    assign(socket, :current_topic, nil)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold mb-6">{gettext("Matches")}</h1>

      <%= if @loading do %>
        <.loading_spinner message={gettext("Loading your matches...")} />
      <% else %>
        <%= if @ai_match do %>
          <.ai_match_card ai_match={@ai_match} />
        <% end %>

        <%= if @matches == [] do %>
          <.empty_state />
        <% else %>
          <div class={[
            "grid gap-4 md:grid-cols-[20rem_minmax(0,1fr)] md:items-start",
            if(@selected_match_id, do: "grid-cols-1", else: "grid-cols-1")
          ]}>
            <aside class={[
              "space-y-2 md:block",
              if(@selected_match_id, do: "hidden", else: "block")
            ]}>
              <%= for match_data <- @matches do %>
                <.match_row
                  match_data={match_data}
                  selected={@selected_match_id == match_data.match.id}
                />
              <% end %>
            </aside>

            <section
              id="chat-pane"
              class={[
                "md:block",
                if(@selected_match_id, do: "block", else: "hidden")
              ]}
            >
              <%= if @selected_match_id do %>
                <div
                  id="chat-container"
                  phx-hook="ScrollToBottom"
                  class="flex flex-col bg-white rounded-2xl shadow-md overflow-hidden h-[calc(100vh-12rem)] min-h-[24rem]"
                >
                  <.chat_header
                    other_profile={@other_profile}
                    back_action="close_chat"
                  />
                  <.messages_list
                    messages={@messages}
                    other_profile={@other_profile}
                    current_user_id={@user.id}
                  />
                  <.message_input form={@message_form} />
                </div>
              <% else %>
                <.chat_placeholder />
              <% end %>
            </section>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <div class="text-6xl mb-4">💝</div>
      <p class="text-gray-500 text-lg font-medium">{gettext("No matches yet")}</p>
      <p class="text-gray-400 mt-2">{gettext("Keep swiping to find your perfect match!")}</p>
      <.link
        navigate={~p"/discover"}
        class="inline-block mt-6 bg-red-500 hover:bg-red-600 text-white font-semibold py-3 px-6 rounded-full transition-colors"
      >
        {gettext("Start Discovering")}
      </.link>
    </div>
    """
  end

  defp chat_placeholder(assigns) do
    ~H"""
    <div class="hidden md:flex flex-col items-center justify-center bg-white rounded-2xl shadow-md h-[calc(100vh-12rem)] min-h-[24rem] text-center px-8">
      <div class="text-6xl mb-4">💬</div>
      <p class="text-gray-500 text-lg font-medium">{gettext("Pick a match to chat")}</p>
      <p class="text-gray-400 mt-2">{gettext("Their conversation will appear here.")}</p>
    </div>
    """
  end

  attr :match_data, :map, required: true
  attr :selected, :boolean, default: false

  defp match_row(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="select_match"
      phx-value-match-id={@match_data.match.id}
      class={[
        "w-full flex items-center gap-4 p-4 rounded-xl shadow-sm hover:shadow-md transition text-left",
        if(@selected,
          do: "bg-red-50 border-2 border-red-300",
          else: "bg-white border border-transparent"
        ),
        @match_data.is_new_match && !@selected && "bg-red-50 border-red-200"
      ]}
    >
      <div class="relative shrink-0">
        <%= if @match_data.other_profile && @match_data.other_profile.profile_picture do %>
          <img
            src={@match_data.other_profile.profile_picture}
            alt={"#{@match_data.other_profile.first_name}'s photo"}
            class="w-14 h-14 rounded-full object-cover"
          />
        <% else %>
          <div class="w-14 h-14 rounded-full bg-gray-200 flex items-center justify-center">
            <span class="text-gray-400 text-2xl" aria-hidden="true">👤</span>
          </div>
        <% end %>
        <%= if @match_data.unread_count > 0 do %>
          <span class="absolute -top-1 -right-1 bg-red-500 text-white text-xs font-bold rounded-full h-5 min-w-5 px-1 flex items-center justify-center">
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
            <span class="text-xs font-semibold text-red-500 bg-red-100 px-2 py-0.5 rounded-full whitespace-nowrap">
              {gettext("NEW MATCH")}
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
    </button>
    """
  end

  attr :ai_match, :map, required: true

  defp ai_match_card(assigns) do
    ~H"""
    <section class="mb-6 rounded-2xl bg-gradient-to-r from-red-50 via-white to-red-50 border border-red-200 shadow-md p-5">
      <div class="flex items-start gap-4">
        <div class="shrink-0">
          <%= if @ai_match.profile.profile_picture do %>
            <img
              src={@ai_match.profile.profile_picture}
              alt={"#{@ai_match.profile.first_name}'s photo"}
              class="w-20 h-20 rounded-full object-cover border-4 border-red-200"
            />
          <% else %>
            <div class="w-20 h-20 rounded-full bg-gray-200 flex items-center justify-center border-4 border-red-200">
              <span class="text-gray-400 text-3xl" aria-hidden="true">👤</span>
            </div>
          <% end %>
        </div>

        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 mb-1">
            <span class="text-xs font-semibold uppercase tracking-wide text-red-600 bg-red-100 px-2 py-0.5 rounded-full">
              {gettext("AI Match")}
            </span>
            <span class="text-xs text-gray-400">{gettext("picked just for you")}</span>
          </div>
          <h2 class="text-lg font-bold text-gray-900">
            {display_name(@ai_match.profile)}
          </h2>
          <%= if @ai_match.profile.bio do %>
            <p class="text-sm text-gray-500 mt-1 line-clamp-2">{@ai_match.profile.bio}</p>
          <% end %>

          <%= if @ai_match.reasons != [] do %>
            <ul class="flex flex-wrap gap-2 mt-3">
              <%= for reason <- @ai_match.reasons do %>
                <li class="text-xs text-red-700 bg-red-100 px-3 py-1 rounded-full">
                  {ai_reason_text(reason)}
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  defp ai_reason_text({:age, _}), do: gettext("Within your preferred age range")

  defp ai_reason_text({:country, %{country: country}}),
    do: gettext("Lives in %{country}", country: country)

  defp ai_reason_text({:religion, _}), do: gettext("Same religion")

  defp ai_reason_text({:interests, %{list: list}}),
    do: gettext("Shared interests: %{list}", list: Enum.join(list, ", "))

  defp ai_reason_text({:languages, %{list: list}}),
    do: gettext("Shared languages: %{list}", list: Enum.join(list, ", "))

  defp message_preview(nil), do: gettext("Start a conversation!")
  defp message_preview(message), do: truncate_message(message.content)

  defp truncate_message(content) when byte_size(content) > 50 do
    String.slice(content, 0, 47) <> "..."
  end

  defp truncate_message(content), do: content
end
