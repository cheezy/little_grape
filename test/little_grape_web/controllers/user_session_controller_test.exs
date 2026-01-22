defmodule LittleGrapeWeb.UserSessionControllerTest do
  use LittleGrapeWeb.ConnCase, async: true

  import LittleGrape.AccountsFixtures
  alias LittleGrape.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "GET /users/log-in" do
    test "renders login page", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in")
      response = html_response(conn, 200)
      # Check for form elements (locale-agnostic)
      # The login page now shows both forms (magic link and password) on the same page
      assert response =~ ~s(name="user[email]")
      assert response =~ ~p"/users/register"
      assert response =~ ~s(name="user[password]")
    end

    test "renders login page with email filled in when logged in", %{conn: conn, user: user} do
      html =
        conn
        |> log_in_user(user)
        |> get(~p"/users/log-in")
        |> html_response(200)

      # Check for email input with user's email (locale-agnostic)
      # The email should be pre-filled and the input should be readonly
      assert html =~ ~s(name="user[email]")
      assert html =~ ~s(value="#{user.email}")
      assert html =~ ~s(readonly)
    end

    test "renders login page (email + password)", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in?mode=password")
      response = html_response(conn, 200)
      # Check for form elements (locale-agnostic)
      assert response =~ ~s(name="user[email]")
      assert response =~ ~s(name="user[password]")
      assert response =~ ~p"/users/register"
    end
  end

  describe "GET /users/log-in/:token" do
    test "renders confirmation page for unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      conn = get(conn, ~p"/users/log-in/#{token}")
      html = html_response(conn, 200)
      # Check for password field (confirmation requires setting password)
      assert html =~ ~s(name="user[password]")
      # The _action=confirmed is passed via URL query parameter
      assert html =~ ~s(_action=confirmed)
    end

    test "renders login page for confirmed user", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      conn = get(conn, ~p"/users/log-in/#{token}")
      html = html_response(conn, 200)
      # Confirmed user doesn't need password confirmation (no _action=confirmed in URL)
      refute html =~ ~s(_action=confirmed)
      assert html =~ ~s(name="user[token]")
    end

    test "raises error for invalid token", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in/invalid-token")
      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Magic link is invalid or it has expired."
    end

    test "redirects to login for expired token", %{conn: conn, user: user} do
      {token, hashed_token} = generate_user_magic_link_token(user)
      # Expire the token by offsetting its timestamp
      offset_user_token(hashed_token, -20, :minute)

      conn = get(conn, ~p"/users/log-in/#{token}")
      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Magic link is invalid or it has expired."
    end

    test "allows access to confirm page when already logged in", %{conn: conn, user: user} do
      # Generate a token for a different purpose (e.g., re-authentication)
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/users/log-in/#{token}")

      html = html_response(conn, 200)
      assert html =~ ~s(name="user[token]")
    end
  end

  describe "POST /users/log-in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/profile"
      assert response =~ ~p"/users/log-out"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_little_grape_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "emits error message with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      response = html_response(conn, 200)
      # Check we're still on login page with form (locale-agnostic)
      assert response =~ ~s(name="user[email]")
      assert response =~ ~s(name="user[password]")
    end

    test "emits error for non-existent email", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => "nonexistent@example.com", "password" => "SomePassword1!"}
        })

      response = html_response(conn, 200)
      # Same error message to prevent user enumeration
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid email or password"
      assert response =~ ~s(name="user[email]")
    end

    test "does not log in unconfirmed user without password", %{conn: conn, unconfirmed_user: user} do
      # Unconfirmed users don't have a password set, so password login should fail
      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "AnyPassword1!"}
        })

      assert html_response(conn, 200)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid email or password"
      refute get_session(conn, :user_token)
    end
  end

  describe "POST /users/log-in - magic link" do
    test "sends magic link email when user exists", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      assert LittleGrape.Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "login"
    end

    test "does not reveal whether email exists for non-existent user", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => "nonexistent@example.com"}
        })

      # Same message as when user exists to prevent enumeration
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/profile"
      assert response =~ ~p"/users/log-out"
    end

    test "confirms unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "token" => token,
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          },
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "User confirmed successfully."

      assert Accounts.get_user!(user.id).confirmed_at

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/profile"
      assert response =~ ~p"/users/log-out"
    end

    test "emits error message when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => "invalid"}
        })

      assert html_response(conn, 200) =~ "The link is invalid or it has expired."
    end

    test "rejects confirmation with invalid password", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "token" => token,
            "password" => "short",
            "password_confirmation" => "short"
          },
          "_action" => "confirmed"
        })

      response = html_response(conn, 200)
      # Should stay on confirm page with error
      assert response =~ ~s(name="user[password]")
      refute get_session(conn, :user_token)
    end

    test "rejects confirmation with mismatched password confirmation", %{
      conn: conn,
      unconfirmed_user: user
    } do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "token" => token,
            "password" => valid_user_password(),
            "password_confirmation" => "DifferentPassword1!"
          },
          "_action" => "confirmed"
        })

      response = html_response(conn, 200)
      # Should stay on confirm page with error
      assert response =~ ~s(name="user[password]")
      refute get_session(conn, :user_token)
    end

    test "rejects expired magic link token", %{conn: conn, user: user} do
      {token, hashed_token} = generate_user_magic_link_token(user)
      # Offset the token to be expired (more than 15 minutes old)
      offset_user_token(hashed_token, -20, :minute)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert html_response(conn, 200) =~ "The link is invalid or it has expired."
      refute get_session(conn, :user_token)
    end

    test "logs in with remember me via magic link", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token, "remember_me" => "true"}
        })

      assert conn.resp_cookies["_little_grape_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
