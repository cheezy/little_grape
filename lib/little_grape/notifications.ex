defmodule LittleGrape.Notifications do
  @moduledoc """
  The Notifications context.

  Handles broadcasting notifications to users for various events
  like matches, messages, and other real-time updates.
  """

  @doc """
  Notifies both users when a match occurs.

  Broadcasts a {:new_match, match} message to each user's notification topic.

  ## Parameters

    * `match` - The match struct containing user_a_id and user_b_id

  ## Examples

      iex> notify_match(match)
      :ok

  """
  def notify_match(%{user_a_id: user_a_id, user_b_id: user_b_id} = match) do
    # Broadcast to user_a's notification topic
    Phoenix.PubSub.broadcast(
      LittleGrape.PubSub,
      "user:#{user_a_id}",
      {:new_match, match}
    )

    # Broadcast to user_b's notification topic
    Phoenix.PubSub.broadcast(
      LittleGrape.PubSub,
      "user:#{user_b_id}",
      {:new_match, match}
    )

    :ok
  end

  @doc """
  Notifies the recipient of a new message.

  Broadcasts a {:new_message, message} to the recipient's notification topic.
  Does not notify if the recipient is the sender (to avoid self-notifications).

  ## Parameters

    * `recipient_id` - The ID of the user to notify
    * `message` - The message struct containing sender_id

  ## Returns

    * `:ok` - Notification sent (or skipped if recipient is sender)

  ## Examples

      iex> notify_message(recipient_id, message)
      :ok

  """
  def notify_message(recipient_id, %{sender_id: sender_id} = _message)
      when recipient_id == sender_id do
    # Don't notify user of their own message
    :ok
  end

  def notify_message(recipient_id, message) do
    Phoenix.PubSub.broadcast(
      LittleGrape.PubSub,
      "user:#{recipient_id}",
      {:new_message, message}
    )

    :ok
  end
end
