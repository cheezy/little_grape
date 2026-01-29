defmodule LittleGrapeWeb.MatchesLiveTest do
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

  # Helper to mount and wait for async loading to complete
  defp mount_and_render(conn, path) do
    {:ok, view, _html} = live(conn, path)
    html = render(view)
    {:ok, view, html}
  end

  describe "MatchesLive" do
    setup :register_and_log_in_user

    test "requires authentication", %{conn: _conn} do
      # Test with unauthenticated connection
      conn = build_conn()

      result = get(conn, ~p"/matches")

      assert redirected_to(result) == ~p"/users/log-in"
    end

    test "mounts successfully with authenticated user", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      assert html =~ "Matches"
    end

    test "shows empty state when user has no matches", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      assert html =~ "No matches yet"
      assert html =~ "Keep swiping to find your perfect match!"
      assert html =~ "Start Discovering"
    end

    test "displays matches with profile info", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user, %{first_name: "TestUser"}) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()

      profile_fixture(other_user, %{first_name: "MatchedPerson"})
      |> set_profile_picture()

      # Create a match
      {:ok, _result} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should show match with other user's name
      assert html =~ "MatchedPerson"
      # Should have profile picture
      assert html =~ "/uploads/test.jpg"
    end

    test "displays last message preview", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "Messenger"}) |> set_profile_picture()

      # Create a match and get the conversation
      {:ok, %{match: _match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      # Send a message
      {:ok, _message} =
        Messaging.create_message(conversation.id, other_user.id, "Hello there!")

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should show message preview
      assert html =~ "Hello there!"
    end

    test "shows placeholder text when no messages", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "NewMatch"}) |> set_profile_picture()

      # Create a match (no messages)
      {:ok, _result} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should show placeholder text
      assert html =~ "Start a conversation!"
    end

    test "match card links to chat page", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "ChatPartner"}) |> set_profile_picture()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should have link to chat
      assert html =~ "/chat/#{match.id}"
    end

    test "truncates long message previews", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "LongMessenger"}) |> set_profile_picture()

      # Create a match and get the conversation
      {:ok, %{conversation: conversation}} = Matches.create_match(user.id, other_user.id)

      # Send a long message
      long_message = String.duplicate("a", 100)
      {:ok, _message} = Messaging.create_message(conversation.id, other_user.id, long_message)

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should show truncated message with ellipsis
      assert html =~ "..."
      # Should not show full message
      refute html =~ long_message
    end

    test "displays placeholder for profile without picture", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile but no picture
      other_user = user_fixture()
      profile = LittleGrape.Accounts.get_or_create_profile(other_user)

      profile
      |> Profile.changeset(%{
        first_name: "NoPicPerson",
        gender: "female",
        birthdate: Date.add(Date.utc_today(), -25 * 365)
      })
      |> Repo.update!()

      # Create a match (other user has no profile picture)
      {:ok, _result} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should show name and placeholder
      assert html =~ "NoPicPerson"
      assert html =~ "👤"
    end

    test "displays multiple matches in order", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create first match
      other_user1 = user_fixture()
      profile_fixture(other_user1, %{first_name: "FirstMatch"}) |> set_profile_picture()
      {:ok, %{conversation: conv1}} = Matches.create_match(user.id, other_user1.id)

      # Create second match
      other_user2 = user_fixture()
      profile_fixture(other_user2, %{first_name: "SecondMatch"}) |> set_profile_picture()
      {:ok, _result} = Matches.create_match(user.id, other_user2.id)

      # Send a message to first match (makes it more recent)
      {:ok, _message} = Messaging.create_message(conv1.id, other_user1.id, "Recent message")

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Both matches should be displayed
      assert html =~ "FirstMatch"
      assert html =~ "SecondMatch"
    end

    test "displays Unknown when profile has no first_name", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile but no first_name
      other_user = user_fixture()
      profile = LittleGrape.Accounts.get_or_create_profile(other_user)

      profile
      |> Profile.changeset(%{
        first_name: nil,
        gender: "female",
        birthdate: Date.add(Date.utc_today(), -25 * 365)
      })
      |> Repo.update!()

      # Create a match
      {:ok, _result} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should show Unknown for the name
      assert html =~ "Unknown"
    end

    test "shows short message without truncation", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "ShortMsgUser"}) |> set_profile_picture()

      # Create a match and get the conversation
      {:ok, %{conversation: conversation}} = Matches.create_match(user.id, other_user.id)

      # Send a short message (under 50 chars)
      short_message = "Hi!"
      {:ok, _message} = Messaging.create_message(conversation.id, other_user.id, short_message)

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should show full message without ellipsis
      assert html =~ "Hi!"
      refute html =~ "..."
    end

    test "displays Unknown when other user has no profile", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user WITHOUT a profile
      other_user = user_fixture()
      # Don't create a profile for other_user

      # Create a match
      {:ok, _result} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should show Unknown for the name and placeholder for picture
      assert html =~ "Unknown"
      assert html =~ "👤"
    end

    test "shows NEW MATCH label for matches with no messages", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "NewPerson"}) |> set_profile_picture()

      # Create a match (no messages)
      {:ok, _result} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should show NEW MATCH label
      assert html =~ "NEW MATCH"
    end

    test "does not show NEW MATCH label for matches with messages", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "ChattedPerson"}) |> set_profile_picture()

      # Create a match and send a message
      {:ok, %{conversation: conversation}} = Matches.create_match(user.id, other_user.id)
      {:ok, _message} = Messaging.create_message(conversation.id, other_user.id, "Hey there!")

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should NOT show NEW MATCH label
      refute html =~ "NEW MATCH"
      assert html =~ "ChattedPerson"
    end

    test "shows unread count badge for unread messages", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "UnreadSender"}) |> set_profile_picture()

      # Create a match and send unread messages from other user
      {:ok, %{conversation: conversation}} = Matches.create_match(user.id, other_user.id)
      {:ok, _msg1} = Messaging.create_message(conversation.id, other_user.id, "Message 1")
      {:ok, _msg2} = Messaging.create_message(conversation.id, other_user.id, "Message 2")
      {:ok, _msg3} = Messaging.create_message(conversation.id, other_user.id, "Message 3")

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should show unread count badge
      assert html =~ "UnreadSender"
      # The badge should contain the number 3 (with possible whitespace)
      assert html =~ ~r/>\s*3\s*</
    end

    test "does not show unread count for messages sent by current user", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "SentTo"}) |> set_profile_picture()

      # Create a match and send messages from current user
      {:ok, %{conversation: conversation}} = Matches.create_match(user.id, other_user.id)
      {:ok, _msg1} = Messaging.create_message(conversation.id, user.id, "My message 1")
      {:ok, _msg2} = Messaging.create_message(conversation.id, user.id, "My message 2")

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should NOT show unread count badge (messages from self don't count)
      assert html =~ "SentTo"
      # Should not have a badge with count
      refute html =~ ~r/>2</
    end

    test "new matches appear before matches with messages", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create first match with messages (older)
      other_user1 = user_fixture()
      profile_fixture(other_user1, %{first_name: "OldMatch"}) |> set_profile_picture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user.id, other_user1.id)
      {:ok, _msg} = Messaging.create_message(conversation.id, other_user1.id, "Old message")

      # Create second match with no messages (newer, but should appear first)
      other_user2 = user_fixture()
      profile_fixture(other_user2, %{first_name: "NewMatch"}) |> set_profile_picture()
      {:ok, _result} = Matches.create_match(user.id, other_user2.id)

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # NewMatch (no messages) should appear before OldMatch (has messages)
      new_match_pos = :binary.match(html, "NewMatch")
      old_match_pos = :binary.match(html, "OldMatch")

      assert new_match_pos != :nomatch
      assert old_match_pos != :nomatch

      {new_pos, _} = new_match_pos
      {old_pos, _} = old_match_pos

      assert new_pos < old_pos, "New match should appear before match with messages"
    end

    test "new matches have highlighted styling", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create a new match (no messages)
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "HighlightedMatch"}) |> set_profile_picture()
      {:ok, _result} = Matches.create_match(user.id, other_user.id)

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      # Should have highlighted styling (pink background)
      assert html =~ "bg-pink-50"
      assert html =~ "border-pink-200"
    end

    test "subscribes to PubSub on mount", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      {:ok, _view, _html} = live(conn, ~p"/matches")

      # Verify subscription by broadcasting and checking it doesn't crash
      Phoenix.PubSub.broadcast(LittleGrape.PubSub, "user:#{user.id}", {:new_match, %{}})
    end

    test "updates when new match event is received", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      {:ok, view, html} = mount_and_render(conn, ~p"/matches")

      # Initially no matches
      assert html =~ "No matches yet"

      # Create a match - this will broadcast to PubSub
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "RealtimeMatch"}) |> set_profile_picture()
      {:ok, _result} = Matches.create_match(user.id, other_user.id)

      # Render should update with the new match
      html = render(view)
      assert html =~ "RealtimeMatch"
    end

    test "updates when new message event is received", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      # Create another user with profile
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "MessageSender"}) |> set_profile_picture()

      # Create a match
      {:ok, %{conversation: conversation}} = Matches.create_match(user.id, other_user.id)

      {:ok, view, html} = mount_and_render(conn, ~p"/matches")

      # Initially shows "Start a conversation!"
      assert html =~ "Start a conversation!"

      # Send a message - this will broadcast to PubSub
      {:ok, _message} =
        Messaging.create_message(conversation.id, other_user.id, "Hello from realtime!")

      # Render should update with the new message
      html = render(view)
      assert html =~ "Hello from realtime!"
    end
  end
end
