if Code.ensure_loaded?(Phoenix.Component) do
  defmodule AgentWorkshop.Dashboard.Live.Components do
    @moduledoc false
    use Phoenix.Component

    def status_badge(assigns) do
      ~H"""
      <span class={"badge badge-#{@status}"}>{@status}</span>
      """
    end

    def format_cost(amount) when is_number(amount) do
      "$#{:erlang.float_to_binary(amount / 1, decimals: 2)}"
    end

    def format_cost(_), do: "$0.00"

    def format_elapsed(nil, _), do: ""
    def format_elapsed(_, nil), do: ""

    def format_elapsed(start, :now) do
      seconds = DateTime.diff(DateTime.utc_now(), start)
      format_duration(seconds)
    end

    def format_elapsed(start, finish) do
      seconds = DateTime.diff(finish, start)
      format_duration(seconds)
    end

    defp format_duration(seconds) when seconds < 0, do: "0s"
    defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

    defp format_duration(seconds) when seconds < 3600,
      do: "#{div(seconds, 60)}m#{rem(seconds, 60)}s"

    defp format_duration(seconds) do
      hours = div(seconds, 3600)
      mins = div(rem(seconds, 3600), 60)
      "#{hours}h#{mins}m"
    end

    def format_interval(ms) when ms >= 3_600_000, do: "#{div(ms, 3_600_000)}h"
    def format_interval(ms) when ms >= 60_000, do: "#{div(ms, 60_000)}m"
    def format_interval(ms) when ms >= 1_000, do: "#{div(ms, 1_000)}s"
    def format_interval(ms), do: "#{ms}ms"
  end
end
