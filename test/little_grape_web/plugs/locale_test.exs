defmodule LittleGrapeWeb.Plugs.LocaleTest do
  use LittleGrapeWeb.ConnCase, async: true

  alias LittleGrapeWeb.Plugs.Locale

  # ConnCase's setup pins the process Gettext locale to "en", which is also
  # the test-env default_locale (config/test.exs). For default-fallback tests
  # we first switch to another locale so the assertion proves the plug set it.
  defp locale_conn(query_string \\ "", session \\ %{}) do
    build_conn(:get, "/" <> query_string)
    |> init_test_session(session)
    |> fetch_query_params()
  end

  defp run(conn), do: Locale.call(conn, Locale.init([]))

  describe "call/2 precedence" do
    test "query param wins over session" do
      conn = run(locale_conn("?locale=it", %{"locale" => "de"}))

      assert conn.assigns.locale == "it"
      assert get_session(conn, :locale) == "it"
      assert Gettext.get_locale(LittleGrapeWeb.Gettext) == "it"
    end

    test "invalid param falls back to the default locale, not to the session" do
      # The plug's cond short-circuits on a present param: an invalid value
      # goes through validate_locale/1 straight to the default, never
      # consulting the (valid) session value.
      conn = run(locale_conn("?locale=xx", %{"locale" => "de"}))

      assert conn.assigns.locale == "en"
      assert get_session(conn, :locale) == "en"
    end

    test "session locale is used when no param is present" do
      conn = run(locale_conn("", %{"locale" => "fr"}))

      assert conn.assigns.locale == "fr"
      assert get_session(conn, :locale) == "fr"
      assert Gettext.get_locale(LittleGrapeWeb.Gettext) == "fr"
    end

    test "invalid session locale falls back to the default" do
      conn = run(locale_conn("", %{"locale" => "zz"}))

      assert conn.assigns.locale == "en"
      assert get_session(conn, :locale) == "en"
    end

    test "default locale is used when neither param nor session is present" do
      Gettext.put_locale(LittleGrapeWeb.Gettext, "it")

      conn = run(locale_conn())

      assert conn.assigns.locale == "en"
      assert get_session(conn, :locale) == "en"
      assert Gettext.get_locale(LittleGrapeWeb.Gettext) == "en"
    end

    test "stores the resolved locale in the session, not the raw input" do
      conn = run(locale_conn("?locale=bogus"))

      assert get_session(conn, :locale) == "en"
    end
  end

  describe "on_mount/4" do
    defp socket, do: %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

    test "applies the session locale and assigns it" do
      assert {:cont, socket} = Locale.on_mount(:default, %{}, %{"locale" => "el"}, socket())

      assert socket.assigns.locale == "el"
      assert Gettext.get_locale(LittleGrapeWeb.Gettext) == "el"
    end

    test "invalid session locale falls back to the default" do
      assert {:cont, socket} = Locale.on_mount(:default, %{}, %{"locale" => "zz"}, socket())

      assert socket.assigns.locale == "en"
    end

    test "missing session locale falls back to the default" do
      Gettext.put_locale(LittleGrapeWeb.Gettext, "de")

      assert {:cont, socket} = Locale.on_mount(:default, %{}, %{}, socket())

      assert socket.assigns.locale == "en"
      assert Gettext.get_locale(LittleGrapeWeb.Gettext) == "en"
    end
  end

  describe "locales/0" do
    test "returns the supported locale codes in display order" do
      assert Locale.locales() == ~w(sq en it el de fr)
    end
  end
end
