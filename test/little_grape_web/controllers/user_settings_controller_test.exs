defmodule LittleGrapeWeb.UserSettingsControllerTest do
  use LittleGrapeWeb.ConnCase, async: true

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Accounts

  setup :register_and_log_in_user

  describe "GET /users/settings/email" do
    test "renders email settings page", %{conn: conn} do
      conn = get(conn, ~p"/users/settings/email")
      response = html_response(conn, 200)
      assert response =~ ~s(name="user[email]")
    end

    test "redirects if user is not logged in" do
      conn = build_conn()
      conn = get(conn, ~p"/users/settings/email")
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "GET /users/settings/password" do
    test "renders password settings page", %{conn: conn} do
      conn = get(conn, ~p"/users/settings/password")
      response = html_response(conn, 200)
      assert response =~ ~s(name="user[password]")
    end

    test "redirects if user is not logged in" do
      conn = build_conn()
      conn = get(conn, ~p"/users/settings/password")
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "PUT /users/settings/password" do
    test "updates the user password and resets tokens", %{conn: conn, user: user} do
      new_password_conn =
        put(conn, ~p"/users/settings/password", %{
          "user" => %{
            "password" => "NewValid1!",
            "password_confirmation" => "NewValid1!"
          }
        })

      assert redirected_to(new_password_conn) == ~p"/users/settings/password"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_email_and_password(user.email, "NewValid1!")
    end

    test "does not update password on invalid data", %{conn: conn} do
      old_password_conn =
        put(conn, ~p"/users/settings/password", %{
          "user" => %{
            "password" => "short",
            "password_confirmation" => "does not match"
          }
        })

      response = html_response(old_password_conn, 200)
      assert response =~ ~s(name="user[password]")

      assert get_session(old_password_conn, :user_token) == get_session(conn, :user_token)
    end
  end

  describe "PUT /users/settings/email" do
    @tag :capture_log
    test "updates the user email", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/users/settings/email", %{
          "user" => %{"email" => unique_user_email()}
        })

      assert redirected_to(conn) == ~p"/users/settings/email"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "A link to confirm your email"

      assert Accounts.get_user_by_email(user.email)
    end

    test "does not update email on invalid data", %{conn: conn} do
      conn =
        put(conn, ~p"/users/settings/email", %{
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ ~s(name="user[email]")
    end
  end

  describe "GET /users/settings/email/confirm/:token" do
    setup %{user: user} do
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{token: token, email: email}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      conn = get(conn, ~p"/users/settings/email/confirm/#{token}")
      assert redirected_to(conn) == ~p"/users/settings/email"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Email changed successfully"

      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      conn = get(conn, ~p"/users/settings/email/confirm/#{token}")

      assert redirected_to(conn) == ~p"/users/settings/email"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      conn = get(conn, ~p"/users/settings/email/confirm/oops")
      assert redirected_to(conn) == ~p"/users/settings/email"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"

      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      conn = get(conn, ~p"/users/settings/email/confirm/#{token}")
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
