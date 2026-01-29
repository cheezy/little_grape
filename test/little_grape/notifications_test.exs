defmodule LittleGrape.NotificationsTest do
  use LittleGrape.DataCase

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Matches
  alias LittleGrape.Notifications

  describe "notify_match/1" do
    test "broadcasts to user_a's notification topic" do
      user_a = user_fixture()
      user_b = user_fixture()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user_a.id, user_b.id)

      # Subscribe to user_a's topic
      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user_a.id}")

      # Notify
      assert :ok = Notifications.notify_match(match)

      # Should receive the notification
      assert_receive {:new_match, received_match}
      assert received_match.id == match.id
    end

    test "broadcasts to user_b's notification topic" do
      user_a = user_fixture()
      user_b = user_fixture()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user_a.id, user_b.id)

      # Subscribe to user_b's topic
      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user_b.id}")

      # Notify
      assert :ok = Notifications.notify_match(match)

      # Should receive the notification
      assert_receive {:new_match, received_match}
      assert received_match.id == match.id
    end

    test "broadcasts to BOTH users simultaneously" do
      user_a = user_fixture()
      user_b = user_fixture()

      # Create a match
      {:ok, %{match: match}} = Matches.create_match(user_a.id, user_b.id)

      # Subscribe to both topics
      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user_a.id}")
      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user_b.id}")

      # Notify
      assert :ok = Notifications.notify_match(match)

      # Should receive both notifications
      assert_receive {:new_match, match_a}
      assert_receive {:new_match, match_b}
      assert match_a.id == match.id
      assert match_b.id == match.id
    end

    test "returns :ok" do
      user_a = user_fixture()
      user_b = user_fixture()

      {:ok, %{match: match}} = Matches.create_match(user_a.id, user_b.id)

      assert :ok = Notifications.notify_match(match)
    end

    test "works with match map containing user_a_id and user_b_id" do
      user_a = user_fixture()
      user_b = user_fixture()

      # Create a simple map with the required fields
      match_map = %{user_a_id: user_a.id, user_b_id: user_b.id, id: 123}

      # Subscribe to both topics
      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user_a.id}")
      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user_b.id}")

      assert :ok = Notifications.notify_match(match_map)

      assert_receive {:new_match, _}
      assert_receive {:new_match, _}
    end
  end
end
