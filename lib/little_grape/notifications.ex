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
end
