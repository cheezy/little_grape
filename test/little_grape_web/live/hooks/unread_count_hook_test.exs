defmodule LittleGrapeWeb.Hooks.UnreadCountHookTest do
  use LittleGrapeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LittleGrape.AccountsFixtures
  import LittleGrape.MessagingFixtures

  alias LittleGrape.Matches
  alias LittleGrape.Messaging

  describe "UnreadCountHook (via DiscoverLive)" do
    setup :register_and_log_in_user

    setup %{user: user} do
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      other = user_fixture()
      profile_fixture(other) |> set_profile_picture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user.id, other.id)

      %{other: other, conversation: conversation}
    end

    test "a message sent by the other user updates the unread badge", %{
      conn: conn,
      other: other,
      conversation: conversation
    } do
      {:ok, view, html} = mount_and_render(conn, ~p"/discover")
      refute html =~ "bg-pink-500"

      # The context broadcast to "user:#{id}" reaches the hook subscription
      {:ok, _message} = Messaging.send_message(other, conversation.id, "hello!")

      assert render(view) =~ "bg-pink-500"
    end

    test ":messages_read clears the unread badge", %{
      conn: conn,
      user: user,
      other: other,
      conversation: conversation
    } do
      {:ok, _message} = message_fixture(conversation.id, other.id, "unread one")

      {:ok, view, html} = mount_and_render(conn, ~p"/discover")
      assert html =~ "bg-pink-500"

      Messaging.mark_as_read(user, conversation.id)
      send(view.pid, {:messages_read, %{conversation_id: conversation.id, reader_id: user.id}})

      refute render(view) =~ "bg-pink-500"
    end

    test "duplicate deliveries do not crash the LiveView", %{conn: conn} do
      {:ok, view, _html} = mount_and_render(conn, ~p"/discover")

      for _ <- 1..2 do
        send(view.pid, {:message_received, %{}})
        send(view.pid, {:new_match, %{}})
        send(view.pid, {:messages_read, %{}})
      end

      assert render(view)
      assert Process.alive?(view.pid)
    end

    test "unknown messages fall through without crashing", %{conn: conn} do
      {:ok, view, _html} = mount_and_render(conn, ~p"/discover")

      send(view.pid, {:some_unrelated_event, :x})

      assert render(view)
      assert Process.alive?(view.pid)
    end
  end
end
