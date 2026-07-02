defmodule LittleGrapeWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use LittleGrapeWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @locale_labels %{
    "sq" => "Shqip",
    "en" => "English",
    "it" => "Italiano",
    "el" => "Ελληνικά",
    "de" => "Deutsch",
    "fr" => "Français"
  }
  @locale_options Enum.map(
                    LittleGrapeWeb.Plugs.Locale.locales(),
                    &{&1, Map.fetch!(@locale_labels, &1)}
                  )

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, default: %{}, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :unread_count, :integer, default: 0, doc: "total unread message count for badge"
  attr :inner_content, :any, default: nil, doc: "the inner content for live_session layouts"
  attr :rest, :global

  slot :inner_block

  def app(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <.top_nav
        current_scope={@current_scope}
        unread_count={@unread_count}
        locale={Map.get(assigns, :locale, "sq")}
      />

      <main class="flex-1">
        <%= if @inner_content do %>
          {@inner_content}
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shared site-wide top navigation. Used by `app/1` (LiveViews via the
  `:authenticated_app` live_session) and by every controller-rendered template
  so the header looks the same across the whole app.
  """
  attr :current_scope, :map, default: nil
  attr :unread_count, :integer, default: 0
  attr :locale, :string, default: "sq"

  def top_nav(assigns) do
    ~H"""
    <nav class="bg-white/90 backdrop-blur-sm border-b border-gray-200 px-6 py-4">
      <div class="max-w-7xl mx-auto flex items-center justify-between gap-4">
        <a href={~p"/"} class="inline-flex items-center gap-3 shrink-0">
          <svg viewBox="0 0 100 100" class="h-10 w-10" fill="none">
            <circle cx="50" cy="50" r="48" fill="black" stroke="white" stroke-width="2" />
            <path
              d="M50 75 L25 50 C15 40 15 25 30 20 C40 17 50 25 50 35 C50 25 60 17 70 20 C85 25 85 40 75 50 Z"
              fill="#CC0000"
              stroke="white"
              stroke-width="2"
            />
          </svg>
          <span class="text-gray-900 text-xl font-bold tracking-tight">Zemra Ime</span>
        </a>

        <div class="hidden md:flex items-center gap-6">
          <%= if @current_scope && @current_scope.user do %>
            <span class="text-gray-500 text-sm bg-gray-100 px-3 py-1 rounded-full">
              {@current_scope.user.email}
            </span>
            <.top_nav_link href={~p"/"} label={gettext("Home")} />
            <.top_nav_link href={~p"/discover"} label={gettext("Discover")} />
            <.top_nav_link
              href={~p"/matches"}
              label={gettext("Matches")}
              badge={@unread_count}
            />
            <.top_nav_link href={~p"/users/profile"} label={gettext("Profile")} />
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="text-gray-600 hover:text-red-600 transition font-medium"
            >
              {gettext("Log out")}
            </.link>
          <% else %>
            <.top_nav_link href={~p"/users/log-in"} label={gettext("Log In")} />
            <.link
              href={~p"/users/register"}
              class="bg-red-600 text-white px-5 py-2 rounded-full font-semibold hover:bg-red-700 transition shadow"
            >
              {gettext("Sign Up")}
            </.link>
          <% end %>

          <.language_switcher locale={@locale} />
        </div>

        <div class="flex md:hidden items-center gap-3">
          <.language_switcher locale={@locale} />
          <button
            type="button"
            class="p-2 rounded-lg text-gray-600 hover:text-red-600 hover:bg-gray-100 transition"
            data-toggle-hidden="#mobile-menu, #mobile-menu-open-icon, #mobile-menu-close-icon"
            aria-label={gettext("Toggle menu")}
            aria-controls="mobile-menu"
          >
            <span id="mobile-menu-open-icon" class="block">
              <.icon name="hero-bars-3" class="size-6" />
            </span>
            <span id="mobile-menu-close-icon" class="hidden">
              <.icon name="hero-x-mark" class="size-6" />
            </span>
          </button>
        </div>
      </div>

      <div id="mobile-menu" class="hidden md:hidden mt-4 pt-4 border-t border-gray-200">
        <div class="flex flex-col gap-3">
          <%= if @current_scope && @current_scope.user do %>
            <span class="text-gray-500 text-sm bg-gray-100 px-3 py-1 rounded-full self-start">
              {@current_scope.user.email}
            </span>
            <.top_nav_link href={~p"/"} label={gettext("Home")} />
            <.top_nav_link href={~p"/discover"} label={gettext("Discover")} />
            <.top_nav_link
              href={~p"/matches"}
              label={gettext("Matches")}
              badge={@unread_count}
            />
            <.top_nav_link href={~p"/users/profile"} label={gettext("Profile")} />
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="text-gray-600 hover:text-red-600 transition font-medium"
            >
              {gettext("Log out")}
            </.link>
          <% else %>
            <.top_nav_link href={~p"/users/log-in"} label={gettext("Log In")} />
            <.link
              href={~p"/users/register"}
              class="bg-red-600 text-white px-5 py-2 rounded-full font-semibold hover:bg-red-700 transition shadow self-start"
            >
              {gettext("Sign Up")}
            </.link>
          <% end %>
        </div>
      </div>
    </nav>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :badge, :integer, default: 0

  defp top_nav_link(assigns) do
    ~H"""
    <a href={@href} class="relative text-gray-600 hover:text-red-600 transition font-medium">
      {@label}
      <%= if @badge > 0 do %>
        <span class="absolute -top-2 -right-4 bg-pink-500 text-white text-xs font-bold rounded-full h-5 min-w-5 px-1 flex items-center justify-center">
          {if @badge > 99, do: "99+", else: @badge}
        </span>
      <% end %>
    </a>
    """
  end

  @doc """
  Locale selector offering every supported locale.

  Navigation is handled by a delegated `change` listener in assets/js/app.js
  (keyed on `data-locale-switcher`) that preserves the current path and query
  params. No inline JS (CSP-safe).
  """
  attr :locale, :string, required: true

  def language_switcher(assigns) do
    assigns = assign(assigns, :locale_options, @locale_options)

    ~H"""
    <select
      data-locale-switcher
      aria-label={gettext("Change language")}
      class="px-3 py-1.5 text-sm font-medium text-gray-700 bg-white border border-gray-200 rounded-lg hover:border-gray-300 focus:outline-none focus:ring-2 focus:ring-red-500 cursor-pointer"
    >
      <option :for={{code, label} <- @locale_options} value={code} selected={@locale == code}>
        {label}
      </option>
    </select>
    """
  end

  @doc """
  Card shell for the auth pages (log in, register, confirm): top nav, gradient
  backdrop, centered white card with flash and a title/subtitle header.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :locale, :string, default: "sq"
  attr :title, :string, required: true
  slot :subtitle
  slot :inner_block, required: true

  def auth_card(assigns) do
    ~H"""
    <.top_nav current_scope={@current_scope} locale={@locale} />

    <div class="min-h-screen bg-gradient-to-b from-gray-50 via-white to-gray-100 flex items-center justify-center px-4 py-12">
      <div class="w-full max-w-md">
        <div class="bg-white rounded-3xl shadow-2xl p-8 border border-gray-100">
          <.flash_group flash={@flash} />

          <div class="text-center mb-6">
            <h1 class="text-2xl font-bold text-gray-900 mb-2">{@title}</h1>
            <p :if={@subtitle != []} class="text-gray-600">{render_slot(@subtitle)}</p>
          </div>

          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Card shell for the account settings pages: like `auth_card` but wider and
  top-aligned, with a divider, a cross-link to the sibling settings page, and
  the language switcher below the card.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :locale, :string, default: "sq"
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :link_href, :string, required: true
  attr :link_text, :string, required: true
  slot :inner_block, required: true

  def settings_card(assigns) do
    ~H"""
    <.top_nav current_scope={@current_scope} locale={@locale} />

    <div class="min-h-screen bg-gradient-to-b from-gray-50 via-white to-gray-100 py-12">
      <div class="max-w-2xl mx-auto px-4">
        <div class="bg-white rounded-3xl shadow-2xl p-8 border border-gray-100">
          <.flash_group flash={@flash} />

          <div class="text-center mb-8">
            <h1 class="text-2xl font-bold text-gray-900 mb-2">{@title}</h1>
            <p :if={@subtitle} class="text-gray-600">{@subtitle}</p>
          </div>

          {render_slot(@inner_block)}

          <div class="border-t border-gray-200 my-8"></div>

          <div class="text-center">
            <.link href={@link_href} class="text-red-600 hover:text-red-700 font-medium">
              {@link_text}
            </.link>
          </div>
        </div>

        <div class="mt-6 text-center">
          <.language_switcher locale={@locale} />
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Labeled input matching the auth/settings pages' visual style, with inline
  error rendering for the given form field.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :wrapper_class, :string, default: "mb-4"
  attr :rest, :global, include: ~w(autocomplete required readonly placeholder)

  def auth_input(assigns) do
    ~H"""
    <div class={@wrapper_class}>
      <label class="block text-gray-700 font-medium mb-2">{@label}</label>
      <input
        type={@type}
        name={@field.name}
        value={if @type != "password", do: Phoenix.HTML.Form.normalize_value(@type, @field.value)}
        class="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-red-500 focus:ring-2 focus:ring-red-100 transition outline-none"
        {@rest}
      />
      <.error :for={msg <- @field.errors}>{translate_error(msg)}</.error>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
