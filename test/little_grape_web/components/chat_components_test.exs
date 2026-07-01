defmodule LittleGrapeWeb.ChatComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias LittleGrapeWeb.ChatComponents

  @profile %{first_name: "Ana", profile_picture: nil}

  describe "chat_header/1" do
    test "renders a back navigation link when navigate_back is set" do
      html =
        render_component(&ChatComponents.chat_header/1,
          other_profile: @profile,
          navigate_back: "/matches"
        )

      assert html =~ ~s(href="/matches")
      assert html =~ "Ana"
      refute html =~ "phx-click"
    end

    test "renders a back button when back_action is set" do
      html =
        render_component(&ChatComponents.chat_header/1,
          other_profile: @profile,
          back_action: "close_chat"
        )

      assert html =~ ~s(phx-click="close_chat")
      assert html =~ "Ana"
      refute html =~ "href="
    end

    test "wraps the profile in a clickable button when on_profile_click is set" do
      html =
        render_component(&ChatComponents.chat_header/1,
          other_profile: @profile,
          on_profile_click: "show_profile"
        )

      assert html =~ ~s(phx-click="show_profile")
      assert html =~ "Ana"
    end

    test "renders a pulse skeleton when loading" do
      html =
        render_component(&ChatComponents.chat_header/1,
          navigate_back: "/matches",
          loading: true
        )

      assert html =~ "animate-pulse"
      refute html =~ "Unknown"
    end

    test "escapes user-provided names" do
      html =
        render_component(&ChatComponents.chat_header/1,
          other_profile: %{first_name: "<script>alert(1)</script>", profile_picture: nil}
        )

      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
    end
  end

  describe "display_name/1" do
    test "returns Unknown for a nil profile" do
      assert ChatComponents.display_name(nil) == "Unknown"
    end

    test "returns Unknown when first_name is nil" do
      assert ChatComponents.display_name(%{first_name: nil}) == "Unknown"
    end

    test "returns the first name when present" do
      assert ChatComponents.display_name(%{first_name: "Ana"}) == "Ana"
    end
  end
end
