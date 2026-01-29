defmodule LittleGrapeWeb.ChatLiveTest do
  use LittleGrapeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LittleGrape.AccountsFixtures

  alias LittleGrape.Accounts.Profile
  alias LittleGrape.Matches
  alias LittleGrape.Messaging
  alias LittleGrape.Repo

  # Helper to set profile_picture (required for complete profile)
  defp set_profile_picture(profile) do
    profile
    |> Profile.profile_picture_changeset(%{profile_picture: "/uploads/test.jpg"})
    |> Repo.update!()
  end

  describe "ChatLive" do
    setup :register_and_log_in_user

    test "requires authentication", %{conn: _conn} do
      # Test with unauthenticated connection
      conn = build_conn()

      result = get(conn, ~p"/chat/1")

      assert redirected_to(result) == ~p"/users/log-in"
    end

    test "redirects to matches if match not found", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/chat/999999")

      assert path == "/matches"
      assert flash["error"] == "Conversation not found"
    end

    test "redirects to matches if user is not a participant", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create a match between two OTHER users
      other_user1 = user_fixture()
      other_user2 = user_fixture()
      profile_fixture(other_user1) |> set_profile_picture()
      profile_fixture(other_user2) |> set_profile_picture()

      {:ok, %{match: match}} = Matches.create_match(other_user1.id, other_user2.id)

      {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/chat/#{match.id}")

      assert path == "/matches"
      assert flash["error"] == "Conversation not found"
    end

    test "mounts successfully for authorized user", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user, %{first_name: "TestUser"}) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "ChatPartner"}) |> set_profile_picture()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = live(conn, ~p"/chat/#{match.id}")

      # Should show the chat partner's name
      assert html =~ "ChatPartner"
    end

    test "displays empty state when no messages", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "NewChatPartner"}) |> set_profile_picture()

      # Create a match (no messages)
      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = live(conn, ~p"/chat/#{match.id}")

      # Should show empty state
      assert html =~ "No messages yet"
      assert html =~ "Say hello to NewChatPartner!"
    end

    test "loads and displays messages on mount", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "MessageSender"}) |> set_profile_picture()

      # Create a match and conversation
      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      # Create some messages
      {:ok, _msg1} = Messaging.create_message(conversation.id, other_user.id, "Hello there!")
      {:ok, _msg2} = Messaging.create_message(conversation.id, user.id, "Hi! How are you?")
      {:ok, _msg3} = Messaging.create_message(conversation.id, other_user.id, "Doing great!")

      {:ok, _view, html} = live(conn, ~p"/chat/#{match.id}")

      # All messages should be displayed
      assert html =~ "Hello there!"
      assert html =~ "Hi! How are you?"
      assert html =~ "Doing great!"
    end

    test "displays own messages aligned to the right", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user) |> set_profile_picture()

      # Create a match and conversation
      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      # Create a message from the current user
      {:ok, _msg} = Messaging.create_message(conversation.id, user.id, "My own message")

      {:ok, _view, html} = live(conn, ~p"/chat/#{match.id}")

      # Own messages should have pink background and right alignment
      assert html =~ "My own message"
      assert html =~ "bg-pink-500"
      assert html =~ "justify-end"
    end

    test "displays other's messages aligned to the left", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user) |> set_profile_picture()

      # Create a match and conversation
      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      # Create a message from the other user
      {:ok, _msg} = Messaging.create_message(conversation.id, other_user.id, "Their message")

      {:ok, _view, html} = live(conn, ~p"/chat/#{match.id}")

      # Other's messages should have white background and left alignment
      assert html =~ "Their message"
      assert html =~ "bg-white"
      assert html =~ "justify-start"
    end

    test "displays timestamps on messages", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user) |> set_profile_picture()

      # Create a match and conversation
      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      # Create a message
      {:ok, _msg} = Messaging.create_message(conversation.id, user.id, "Timestamped message")

      {:ok, _view, html} = live(conn, ~p"/chat/#{match.id}")

      # Should contain time format (e.g., "12:34 PM" or "1:23 AM")
      assert html =~ ~r/\d{1,2}:\d{2}\s*[AP]M/i
    end

    test "shows back link to matches", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user) |> set_profile_picture()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = live(conn, ~p"/chat/#{match.id}")

      # Should have a link back to matches
      assert html =~ ~s(href="/matches")
    end

    test "shows profile picture in header when available", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile picture
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "PhotoPerson"}) |> set_profile_picture()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = live(conn, ~p"/chat/#{match.id}")

      # Should show the profile picture
      assert html =~ "/uploads/test.jpg"
    end

    test "shows placeholder when no profile picture", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile but no picture
      other_user = user_fixture()
      profile = LittleGrape.Accounts.get_or_create_profile(other_user)

      profile
      |> Profile.changeset(%{
        first_name: "NoPicUser",
        gender: "female",
        birthdate: Date.add(Date.utc_today(), -25 * 365)
      })
      |> Repo.update!()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = live(conn, ~p"/chat/#{match.id}")

      # Should show placeholder
      assert html =~ "👤"
      assert html =~ "NoPicUser"
    end

    test "shows Unknown when other user has no profile", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user WITHOUT profile
      other_user = user_fixture()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = live(conn, ~p"/chat/#{match.id}")

      # Should show Unknown
      assert html =~ "Unknown"
    end

    test "works when user is user_b in the match", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user, %{first_name: "UserB"}) |> set_profile_picture()

      # Create another user with profile who will be user_a (lower ID)
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "UserA"}) |> set_profile_picture()

      # Create match - IDs are normalized so the other user might be user_a
      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(other_user.id, user.id)

      # Send a message
      {:ok, _msg} = Messaging.create_message(conversation.id, other_user.id, "From UserA")

      {:ok, _view, html} = live(conn, ~p"/chat/#{match.id}")

      # Should work correctly regardless of which position user is in
      assert html =~ "UserA"
      assert html =~ "From UserA"
    end

    test "displays message input form", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user) |> set_profile_picture()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = live(conn, ~p"/chat/#{match.id}")

      # Should show message input form
      assert html =~ "Type a message..."
      assert html =~ "phx-submit=\"send_message\""
    end

    test "sends message when form is submitted", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user) |> set_profile_picture()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, view, _html} = live(conn, ~p"/chat/#{match.id}")

      # Submit a message
      view
      |> form("form", %{content: "Hello from test!"})
      |> render_submit()

      # Message should appear in the view
      html = render(view)
      assert html =~ "Hello from test!"
    end

    test "does not send empty message", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user) |> set_profile_picture()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, view, _html} = live(conn, ~p"/chat/#{match.id}")

      # Submit an empty message
      view
      |> form("form", %{content: ""})
      |> render_submit()

      # Should still show empty state (no message sent)
      html = render(view)
      assert html =~ "No messages yet"
    end

    test "does not send whitespace-only message", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user) |> set_profile_picture()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, view, _html} = live(conn, ~p"/chat/#{match.id}")

      # Submit whitespace-only message
      view
      |> form("form", %{content: "   "})
      |> render_submit()

      # Should still show empty state (no message sent)
      html = render(view)
      assert html =~ "No messages yet"
    end

    test "receives new messages in real-time via PubSub", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user) |> set_profile_picture()

      # Create a match
      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      {:ok, view, html} = live(conn, ~p"/chat/#{match.id}")

      # Initially empty
      assert html =~ "No messages yet"

      # Other user sends a message (simulating real-time)
      {:ok, _message} = Messaging.send_message(other_user, conversation.id, "Real-time message!")

      # Should appear in the view
      html = render(view)
      assert html =~ "Real-time message!"
    end

    test "subscribes to conversation topic on mount", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user) |> set_profile_picture()

      # Create a match
      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      {:ok, view, _html} = live(conn, ~p"/chat/#{match.id}")

      # Simulate incoming message via PubSub
      message = %{
        id: 999,
        content: "PubSub test message",
        sender_id: other_user.id,
        conversation_id: conversation.id,
        inserted_at: DateTime.utc_now()
      }

      send(view.pid, {:new_message, message})

      # Should appear in the view
      html = render(view)
      assert html =~ "PubSub test message"
    end
  end
end
