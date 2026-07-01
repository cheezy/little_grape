defmodule LittleGrapeWeb.ChatComponents do
  @moduledoc """
  Function components for rendering a chat conversation. Used by `ChatLive`
  (full-page chat at `/chat/:match_id`) and `MatchesLive` (embedded chat
  pane in the master-detail matches view).
  """
  use Phoenix.Component
  use Gettext, backend: LittleGrapeWeb.Gettext

  attr :other_profile, :any, default: nil
  attr :back_action, :any, default: nil, doc: "phx-click event for a back button"
  attr :navigate_back, :string, default: nil, doc: "path for a back navigation link"

  attr :on_profile_click, :string,
    default: nil,
    doc: "phx-click event fired when tapping the photo/name"

  attr :loading, :boolean, default: false, doc: "render a pulse skeleton instead of the profile"

  def chat_header(assigns) do
    ~H"""
    <div class="flex items-center gap-3 px-4 py-3 bg-white border-b shadow-sm">
      <%= if @navigate_back do %>
        <.link
          navigate={@navigate_back}
          class="text-gray-500 hover:text-gray-700"
          aria-label={gettext("Back")}
        >
          <.back_chevron />
        </.link>
      <% end %>
      <%= if @back_action do %>
        <button
          type="button"
          phx-click={@back_action}
          class="text-gray-500 hover:text-gray-700"
          aria-label={gettext("Back")}
        >
          <.back_chevron />
        </button>
      <% end %>

      <%= if @loading do %>
        <div class="flex items-center gap-3 flex-1">
          <div class="w-10 h-10 rounded-full bg-gray-200 animate-pulse"></div>
          <div class="h-4 w-24 bg-gray-200 rounded animate-pulse"></div>
        </div>
      <% else %>
        <%= if @on_profile_click do %>
          <button phx-click={@on_profile_click} class="flex items-center gap-3 flex-1 text-left">
            <.header_identity other_profile={@other_profile} />
          </button>
        <% else %>
          <div class="flex items-center gap-3 flex-1">
            <.header_identity other_profile={@other_profile} />
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp back_chevron(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      class="h-6 w-6"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
    >
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
    </svg>
    """
  end

  attr :other_profile, :any, required: true

  defp header_identity(assigns) do
    ~H"""
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
    <h2 class="font-semibold text-gray-900">{display_name(@other_profile)}</h2>
    """
  end

  attr :messages, :list, required: true
  attr :other_profile, :any, required: true
  attr :current_user_id, :integer, required: true
  attr :container_id, :string, default: "messages-container"
  attr :class, :string, default: "flex-1 overflow-y-auto px-4 py-4 space-y-3 bg-gray-50"

  def messages_list(assigns) do
    ~H"""
    <div id={@container_id} class={@class}>
      <%= if @messages == [] do %>
        <.empty_chat_state other_profile={@other_profile} />
      <% else %>
        <%= for message <- @messages do %>
          <.message_bubble message={message} current_user_id={@current_user_id} />
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :other_profile, :any, required: true

  def empty_chat_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center h-full text-center">
      <div class="text-5xl mb-4">💬</div>
      <p class="text-gray-500 font-medium">{gettext("No messages yet")}</p>
      <p class="text-gray-400 text-sm mt-1">
        {gettext("Say hello to %{name}!", name: display_name(@other_profile))}
      </p>
    </div>
    """
  end

  attr :message, :any, required: true
  attr :current_user_id, :integer, required: true

  def message_bubble(assigns) do
    is_own = assigns.message.sender_id == assigns.current_user_id

    assigns =
      assigns
      |> assign(:is_own, is_own)
      |> assign(:alignment, if(is_own, do: "justify-end", else: "justify-start"))
      |> assign(
        :bubble_style,
        if(is_own,
          do: "bg-red-500 text-white rounded-br-sm",
          else: "bg-white text-gray-900 rounded-bl-sm"
        )
      )

    ~H"""
    <div class={"flex #{@alignment}"}>
      <div class={"max-w-xs px-4 py-2 rounded-2xl shadow-sm #{@bubble_style}"}>
        <p class="break-words">{@message.content}</p>
        <p class={[
          "text-xs mt-1",
          if(@is_own, do: "text-red-200", else: "text-gray-400")
        ]}>
          {format_timestamp(@message.inserted_at)}
        </p>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :form_id, :string, default: "chat-message-form"
  attr :input_id, :string, default: "chat-message-input"

  def message_input(assigns) do
    ~H"""
    <div class="px-4 py-3 bg-white border-t">
      <.form for={@form} id={@form_id} phx-submit="send_message" class="flex gap-2">
        <input
          id={@input_id}
          type="text"
          name={@form[:content].name}
          value={Phoenix.HTML.Form.normalize_value("text", @form[:content].value)}
          placeholder={gettext("Type a message...")}
          autocomplete="off"
          phx-hook="ClearOnEvent"
          class="flex-1 px-4 py-2 border border-gray-300 rounded-full focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-transparent"
        />
        <button
          type="submit"
          class="px-4 py-2 bg-red-500 text-white rounded-full hover:bg-red-600 transition-colors"
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
      </.form>
    </div>
    """
  end

  @doc """
  Formats a `DateTime`/`NaiveDateTime` as 12-hour time, e.g. "3:45 PM".
  """
  def format_timestamp(datetime) do
    hour = datetime.hour
    minute = datetime.minute

    {hour_12, am_pm} =
      if hour >= 12,
        do: {rem(hour - 1, 12) + 1, "PM"},
        else: {if(hour == 0, do: 12, else: hour), "AM"}

    "#{hour_12}:#{String.pad_leading(Integer.to_string(minute), 2, "0")} #{am_pm}"
  end

  @doc """
  Returns the profile's first name, or "Unknown" for nil profiles/names.
  """
  def display_name(nil), do: "Unknown"
  def display_name(profile), do: profile.first_name || "Unknown"
end
