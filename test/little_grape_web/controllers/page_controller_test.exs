defmodule LittleGrapeWeb.PageControllerTest do
  use LittleGrapeWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    # Check for elements that exist on the home page (locale-agnostic)
    assert response =~ "Zemra Ime"
    assert response =~ ~p"/users/register"
    assert response =~ ~p"/users/log-in"
  end
end
