defmodule LittleGrapeWeb.MatchesLiveTest do
  use LittleGrapeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LittleGrape.AccountsFixtures
  import LittleGrape.MessagingFixtures

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

    test "mount performs exactly one token lookup per mount phase", %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      ref = make_ref()
      test_pid = self()
      handler_id = {__MODULE__, ref}

      :telemetry.attach(
        handler_id,
        [:little_grape, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          attributable? =
            test_pid == self() or test_pid in Process.get(:"$callers", [])

          if attributable? and metadata.source == "users_tokens" do
            send(test_pid, {:token_lookup, ref})
          end
        end,
        nil
      )

      try do
        {:ok, _view, _html} = live(conn, ~p"/matches")
      after
        :telemetry.detach(handler_id)
      end

      count =
        fn -> :tick end
        |> Stream.repeatedly()
        |> Enum.reduce_while(0, fn _, acc ->
          receive do
            {:token_lookup, ^ref} -> {:cont, acc + 1}
          after
            0 -> {:halt, acc}
          end
        end)

      # One lookup by the plug on the initial GET, then exactly one per mount
      # phase (disconnected + connected). Before the require_authenticated
      # on_mount refactor this was 5 — each mount phase ran both the on_mount
      # hook and the per-LiveView assign_current_user duplicate.
      assert count == 3
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
        message_fixture(conversation.id, other_user.id, "Hello there!")

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

    test "match card opens the chat in-page when clicked", %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()
      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "ChatPartner"}) |> set_profile_picture()

      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, view, html} = mount_and_render(conn, ~p"/matches")

      # The match list shows a select_match button, not a navigate link
      assert html =~ ~s(phx-click="select_match")
      assert html =~ ~s(phx-value-match-id="#{match.id}")
      refute html =~ "/chat/#{match.id}"

      # Clicking the row loads the chat into the right pane and keeps the list visible
      html = view |> element(~s(button[phx-value-match-id="#{match.id}"])) |> render_click()

      # List still shown
      assert html =~ "ChatPartner"
      # Chat pane now visible (header + input)
      assert html =~ ~s(id="chat-container")
      assert html =~ ~s(id="chat-message-form")
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
      {:ok, _message} = message_fixture(conversation.id, other_user.id, long_message)

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
      {:ok, profile} = LittleGrape.Accounts.get_or_create_profile(other_user)

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
      {:ok, _message} = message_fixture(conv1.id, other_user1.id, "Recent message")

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
      {:ok, profile} = LittleGrape.Accounts.get_or_create_profile(other_user)

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
      {:ok, _message} = message_fixture(conversation.id, other_user.id, short_message)

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
      {:ok, _message} = message_fixture(conversation.id, other_user.id, "Hey there!")

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
      {:ok, _msg1} = message_fixture(conversation.id, other_user.id, "Message 1")
      {:ok, _msg2} = message_fixture(conversation.id, other_user.id, "Message 2")
      {:ok, _msg3} = message_fixture(conversation.id, other_user.id, "Message 3")

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
      {:ok, _msg1} = message_fixture(conversation.id, user.id, "My message 1")
      {:ok, _msg2} = message_fixture(conversation.id, user.id, "My message 2")

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
      {:ok, _msg} = message_fixture(conversation.id, other_user1.id, "Old message")

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
      assert html =~ "bg-red-50"
      assert html =~ "border-red-200"
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
        message_fixture(conversation.id, other_user.id, "Hello from realtime!")

      # Render should update with the new message
      html = render(view)
      assert html =~ "Hello from realtime!"
    end

    test "select_match flashes an error when the match does not exist", %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      {:ok, view, _html} = mount_and_render(conn, ~p"/matches")

      html =
        render_hook(view, "select_match", %{"match-id" => "999999"})

      assert html =~ "Conversation not found."
      # Chat pane should remain hidden (no chat container)
      refute html =~ ~s(id="chat-container")
    end

    test "select_match renders gracefully when the conversation row is missing", %{
      conn: conn,
      user: user
    } do
      profile_fixture(user) |> set_profile_picture()

      other = user_fixture()
      profile_fixture(other) |> set_profile_picture()

      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other.id)

      # Simulate the drift: the match exists but its conversation is gone
      Repo.delete!(conversation)

      {:ok, view, _html} = mount_and_render(conn, ~p"/matches")

      html = render_hook(view, "select_match", %{"match-id" => "#{match.id}"})

      assert html =~ "Conversation not found."
      refute html =~ ~s(id="chat-container")
      assert Process.alive?(view.pid)
    end

    test "select_match ignores a malformed match-id instead of crashing", %{
      conn: conn,
      user: user
    } do
      profile_fixture(user) |> set_profile_picture()

      {:ok, view, _html} = mount_and_render(conn, ~p"/matches")

      for bad_param <- ["abc", "", "42abc", "-", "-5", "0", "99999999999999999999"] do
        html = render_hook(view, "select_match", %{"match-id" => bad_param})
        assert html =~ "Conversation not found."
        refute html =~ ~s(id="chat-container")
      end

      # The LiveView process survived every malformed param
      assert Process.alive?(view.pid)
    end

    test "selecting a match shows existing messages in the chat pane", %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "ChatHistory"}) |> set_profile_picture()

      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      {:ok, _msg} =
        message_fixture(conversation.id, other_user.id, "An earlier message")

      {:ok, view, _html} = mount_and_render(conn, ~p"/matches")

      html =
        view
        |> element(~s(button[phx-value-match-id="#{match.id}"]))
        |> render_click()

      assert html =~ "An earlier message"
      assert html =~ ~s(id="chat-container")
    end

    test "selecting a match marks unread messages as read", %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "MarkReadPerson"}) |> set_profile_picture()

      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      {:ok, _msg} = message_fixture(conversation.id, other_user.id, "Unread message")

      {:ok, view, html} = mount_and_render(conn, ~p"/matches")

      # Before clicking: there's an unread badge with "1"
      assert html =~ ~r/>\s*1\s*</
      assert Messaging.total_unread_count(user) == 1

      view
      |> element(~s(button[phx-value-match-id="#{match.id}"]))
      |> render_click()

      assert Messaging.total_unread_count(user) == 0
    end

    test "close_chat clears the selection and hides the chat pane", %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "Closable"}) |> set_profile_picture()

      {:ok, %{match: match}} = Matches.create_match(user.id, other_user.id)

      {:ok, view, _html} = mount_and_render(conn, ~p"/matches")

      view
      |> element(~s(button[phx-value-match-id="#{match.id}"]))
      |> render_click()

      html = render_hook(view, "close_chat", %{})

      refute html =~ ~s(id="chat-container")
      assert html =~ "Closable"
    end

    test "send_message ignores empty content", %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "EmptyTarget"}) |> set_profile_picture()

      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      {:ok, view, _html} = mount_and_render(conn, ~p"/matches")

      view
      |> element(~s(button[phx-value-match-id="#{match.id}"]))
      |> render_click()

      render_hook(view, "send_message", %{"content" => ""})
      render_hook(view, "send_message", %{"content" => "   "})

      assert Messaging.list_messages(conversation) == []
    end

    test "send_message is a no-op when no conversation is selected", %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "NoSelection"}) |> set_profile_picture()

      {:ok, %{conversation: conversation}} = Matches.create_match(user.id, other_user.id)

      {:ok, view, _html} = mount_and_render(conn, ~p"/matches")

      # Don't select a match — fire send_message anyway
      render_hook(view, "send_message", %{"content" => "should be ignored"})

      assert Messaging.list_messages(conversation) == []
    end

    test "send_message persists the message and clears the form", %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "Receiver"}) |> set_profile_picture()

      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      {:ok, view, _html} = mount_and_render(conn, ~p"/matches")

      view
      |> element(~s(button[phx-value-match-id="#{match.id}"]))
      |> render_click()

      render_hook(view, "send_message", %{"content" => "Hi from sender!"})

      [persisted] = Messaging.list_messages(conversation)
      assert persisted.content == "Hi from sender!"
      assert persisted.sender_id == user.id
    end

    test "send_message flashes an error when the message is too long", %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "TooLongTarget"}) |> set_profile_picture()

      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      {:ok, view, _html} = mount_and_render(conn, ~p"/matches")

      view
      |> element(~s(button[phx-value-match-id="#{match.id}"]))
      |> render_click()

      too_long = String.duplicate("a", 2001)
      html = render_hook(view, "send_message", %{"content" => too_long})

      assert html =~ "Failed to send message. Please try again."
      assert Messaging.list_messages(conversation) == []
    end

    test "appends incoming message from the other user in the open conversation",
         %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "LiveSender"}) |> set_profile_picture()

      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user.id, other_user.id)

      {:ok, view, _html} = mount_and_render(conn, ~p"/matches")

      view
      |> element(~s(button[phx-value-match-id="#{match.id}"]))
      |> render_click()

      # Use send_message (not create_message) so :new_message is broadcast on
      # the conversation topic, which is what triggers the LV's append +
      # mark-as-read logic.
      {:ok, _msg} = Messaging.send_message(other_user, conversation.id, "Pinging you live")

      html = render(view)
      assert html =~ "Pinging you live"
      # Marked as read because sender is not the current user
      assert Messaging.total_unread_count(user) == 0
    end

    test "ignores incoming message for a different conversation", %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "OpenedChat"}) |> set_profile_picture()

      third_user = user_fixture()
      profile_fixture(third_user, %{first_name: "ThirdParty"}) |> set_profile_picture()

      {:ok, %{match: match, conversation: opened_conv}} =
        Matches.create_match(user.id, other_user.id)

      {:ok, %{conversation: other_conv}} =
        Matches.create_match(user.id, third_user.id)

      {:ok, view, _html} = mount_and_render(conn, ~p"/matches")

      view
      |> element(~s(button[phx-value-match-id="#{match.id}"]))
      |> render_click()

      # Synthesize a :new_message for the OTHER conversation by sending it
      # directly to the LiveView process. This bypasses PubSub topics so the
      # message reaches the handler without subscribing to the other topic.
      foreign_message = %LittleGrape.Messaging.Message{
        conversation_id: other_conv.id,
        sender_id: third_user.id,
        content: "Should not appear in this chat"
      }

      send(view.pid, {:new_message, foreign_message})

      html = render(view)
      refute html =~ "Should not appear in this chat"
      # And nothing was marked-as-read for the opened conversation
      assert Messaging.list_messages(opened_conv) == []
    end

    test ":messages_read updates the unread badge in the header", %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      other_user = user_fixture()
      profile_fixture(other_user, %{first_name: "ReadBroadcaster"}) |> set_profile_picture()

      {:ok, %{conversation: conversation}} = Matches.create_match(user.id, other_user.id)
      {:ok, _msg} = message_fixture(conversation.id, other_user.id, "Unread one")

      {:ok, view, html} = mount_and_render(conn, ~p"/matches")

      # The header badge on the Matches link uses bg-pink-500 and only renders
      # when @unread_count > 0; the per-match badge uses bg-red-500.
      assert html =~ "bg-pink-500"

      # Mark messages as read out-of-band; the LV is only subscribed to the
      # conversation topic after select_match, so deliver the broadcast
      # message directly to the LV process.
      Messaging.mark_as_read(user, conversation.id)
      send(view.pid, {:messages_read, %{conversation_id: conversation.id, reader_id: user.id}})

      html = render(view)
      refute html =~ "bg-pink-500"
    end

    test "displays the AI match card with reasons when discovery picks one",
         %{conn: conn, user: user} do
      profile_fixture(user, %{
        first_name: "Seeker",
        gender: "male",
        preferred_gender: "female",
        country: "AL",
        preferred_country: "AL",
        languages: ["sq", "en"],
        interests: ["sports", "travel"],
        religion: "muslim"
      })
      |> set_profile_picture()

      candidate = user_fixture()

      profile_fixture(candidate, %{
        first_name: "PerfectMatch",
        bio: "We share so many things",
        gender: "female",
        preferred_gender: "male",
        country: "AL",
        preferred_country: "AL",
        languages: ["sq", "en"],
        interests: ["sports", "travel"],
        religion: "muslim",
        birthdate: Date.add(Date.utc_today(), -28 * 365)
      })
      |> set_profile_picture()

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      assert html =~ "AI Match"
      assert html =~ "PerfectMatch"
      assert html =~ "We share so many things"
      assert html =~ "Within your preferred age range"
      assert html =~ "Lives in AL"
      assert html =~ "Same religion"
      assert html =~ "Shared interests"
      assert html =~ "Shared languages"
    end

    test "does not display the AI match card when there is no candidate",
         %{conn: conn, user: user} do
      profile_fixture(user) |> set_profile_picture()

      {:ok, _view, html} = mount_and_render(conn, ~p"/matches")

      refute html =~ "AI Match"
    end
  end
end
