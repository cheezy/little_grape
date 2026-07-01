defmodule LittleGrapeWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias LittleGrapeWeb.CoreComponents

  describe "loading_spinner/1" do
    test "renders the message with the default wrapper class" do
      html = render_component(&CoreComponents.loading_spinner/1, message: "Loading things...")

      assert html =~ "Loading things..."
      assert html =~ "flex flex-col items-center justify-center py-20"
      assert html =~ "animate-spin"
    end

    test "renders with a custom wrapper class" do
      html =
        render_component(&CoreComponents.loading_spinner/1,
          message: "Loading messages...",
          class: "flex-1 flex flex-col items-center justify-center bg-gray-50"
        )

      assert html =~ "Loading messages..."
      assert html =~ "flex-1 flex flex-col items-center justify-center bg-gray-50"
      refute html =~ "py-20"
    end
  end
end
