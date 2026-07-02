defmodule LittleGrapeWeb.PageControllerTest do
  use LittleGrapeWeb.ConnCase, async: true

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    # Check for elements that exist on the home page (locale-agnostic)
    assert response =~ "Zemra Ime"
    assert response =~ ~p"/users/register"
    assert response =~ ~p"/users/log-in"
  end

  test "CSP script-src does not allow inline scripts", %{conn: conn} do
    conn = get(conn, ~p"/")
    [csp] = get_resp_header(conn, "content-security-policy")

    assert csp =~ "script-src 'self' https://cdn.jsdelivr.net;"
    refute csp =~ "script-src 'self' 'unsafe-inline'"
  end

  test "html lang reflects the current locale", %{conn: conn} do
    # Test default locale is "en" (config/test.exs)
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ ~s(<html lang="en")
  end

  test "switching locale via query param updates session and html lang", %{conn: conn} do
    conn = get(conn, ~p"/?locale=de&foo=bar")

    assert get_session(conn, :locale) == "de"
    assert html_response(conn, 200) =~ ~s(<html lang="de")
  end

  test "unsupported locale value falls back to the default", %{conn: conn} do
    conn = get(conn, ~p"/?locale=xx")

    assert get_session(conn, :locale) == "en"
    assert html_response(conn, 200) =~ ~s(<html lang="en")
  end
end
