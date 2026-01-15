defmodule LittleGrapeWeb.Plugs.Locale do
  @moduledoc """
  A plug that sets the locale based on query params, session, or default.
  """
  import Plug.Conn

  @locales ~w(sq en)
  @default_locale "sq"

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
        @default_locale
    end
  end

  defp validate_locale(locale) when locale in @locales, do: locale
  defp validate_locale(_), do: @default_locale
end
