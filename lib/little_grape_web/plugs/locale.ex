defmodule LittleGrapeWeb.Plugs.Locale do
  @moduledoc """
  A plug that sets the locale based on query params, session, or default.

  Also exposes an `on_mount/4` callback so LiveViews — which run in their own
  process and don't go through the plug pipeline — can pick up the locale from
  the session.
  """
  import Plug.Conn

  @locales ~w(sq en it el de fr)

  @doc "All supported locale codes, in display order."
  def locales, do: @locales

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = get_locale(conn)
    Gettext.put_locale(LittleGrapeWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
  end

  defp get_locale(conn) do
    # Priority: query param > session > default
    cond do
      locale = conn.params["locale"] ->
        validate_locale(locale)

      locale = get_session(conn, :locale) ->
        validate_locale(locale)

      true ->
        default_locale()
    end
  end

  defp validate_locale(locale) when locale in @locales, do: locale
  defp validate_locale(_), do: default_locale()

  defp default_locale do
    Application.get_env(:little_grape, __MODULE__, [])
    |> Keyword.get(:default_locale, "sq")
  end

  @doc """
  LiveView `on_mount` hook: applies the session's locale (if any) so the LiveView
  process renders translations in the same language as the parent request.
  """
  def on_mount(:default, _params, session, socket) do
    locale = validate_locale(session["locale"] || default_locale())
    Gettext.put_locale(LittleGrapeWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end
end
