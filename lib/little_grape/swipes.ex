defmodule LittleGrape.Swipes do
  @moduledoc """
  The Swipes context.
  """

  import Ecto.Query, warn: false

  alias LittleGrape.Accounts.User
  alias LittleGrape.Repo
  alias LittleGrape.Swipes.Swipe

  @doc """
  Creates a swipe record for a user swiping on another user.

  ## Parameters

    * `user` - The user performing the swipe (struct with id)
    * `target_user_id` - The ID of the user being swiped on
    * `action` - Either "like" or "pass"

  ## Returns

    * `{:ok, %Swipe{}}` - Successfully created swipe
    * `{:error, %Ecto.Changeset{}}` - Validation or constraint error

  ## Examples

      iex> create_swipe(user, target_id, "like")
      {:ok, %Swipe{}}

      iex> create_swipe(user, target_id, "invalid")
      {:error, %Ecto.Changeset{}}

      iex> create_swipe(user, same_target_id, "like") # duplicate
      {:error, %Ecto.Changeset{}}

  """
  def create_swipe(%User{id: user_id}, target_user_id, action) do
    %Swipe{}
    |> Swipe.changeset(%{
      user_id: user_id,
      target_user_id: target_user_id,
      action: action
    })
    |> Repo.insert()
  end

  @doc """
  Gets a swipe by user and target user.

  ## Examples

      iex> get_swipe(user_id, target_user_id)
      %Swipe{}

      iex> get_swipe(user_id, non_existent_target_id)
      nil

  """
  def get_swipe(user_id, target_user_id) do
    Repo.get_by(Swipe, user_id: user_id, target_user_id: target_user_id)
  end

  @doc """
  Checks if a user has already swiped on a target user.

  ## Examples

      iex> has_swiped?(user_id, target_user_id)
      true

      iex> has_swiped?(user_id, new_target_user_id)
      false

  """
  def has_swiped?(user_id, target_user_id) do
    query =
      from s in Swipe,
        where: s.user_id == ^user_id and s.target_user_id == ^target_user_id

    Repo.exists?(query)
  end
end
