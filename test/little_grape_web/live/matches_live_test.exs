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

      {:ok, _view, html} = live(conn, ~p"/matches")

      assert html =~ "Matches"
    end

    test "shows empty state when user has no matches", %{conn: conn, user: user} do
      # Create profile for user
      profile_fixture(user) |> set_profile_picture()

      {:ok, _view, html} = live(conn, ~p"/matches")

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

      {:ok, _view, html} = live(conn, ~p"/matches")

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

      {:ok, _view, html} = live(conn, ~p"/matches")

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

      {:ok, _view, html} = live(conn, ~p"/matches")

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

      {:ok, _view, html} = live(conn, ~p"/matches")

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

      {:ok, _view, html} = live(conn, ~p"/matches")

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

      {:ok, _view, html} = live(conn, ~p"/matches")

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

      {:ok, _view, html} = live(conn, ~p"/matches")

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

      {:ok, _view, html} = live(conn, ~p"/matches")

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

      {:ok, _view, html} = live(conn, ~p"/matches")

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

      {:ok, _view, html} = live(conn, ~p"/matches")

      # Should show Unknown for the name and placeholder for picture
      assert html =~ "Unknown"
      assert html =~ "👤"
    end
  end
end
