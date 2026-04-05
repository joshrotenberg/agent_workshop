defmodule AgentWorkshop.Workshop.Display do
  @moduledoc false

  def print_result(name, result) do
    IO.puts("")
    IO.puts(result.result)
    IO.puts("")

    cost_str = if result.cost_usd, do: format_cost(result.cost_usd), else: "n/a"

    IO.puts(
      IO.ANSI.yellow() <>
        "(#{inspect(name)}: #{cost_str} this turn)" <>
        IO.ANSI.reset()
    )
  end

  def print_error(msg) do
    IO.puts(IO.ANSI.red() <> msg <> IO.ANSI.reset())
  end

  def print_info(msg) do
    IO.puts(IO.ANSI.yellow() <> msg <> IO.ANSI.reset())
  end

  def format_status(%{status: :working, queue: [_ | _] = queue}),
    do: "working +#{length(queue)}"

  def format_status(%{status: status}), do: to_string(status)

  def format_cost(amount) when is_number(amount) do
    "$#{:erlang.float_to_binary(amount / 1, decimals: 2)}"
  end

  def format_cost(_), do: "$0.00"

  def truncate(str, max) do
    if String.length(str) > max do
      String.slice(str, 0, max - 3) <> "..."
    else
      str
    end
  end

  def plural(1), do: ""
  def plural(_), do: "s"

  def print_event(entry) do
    time = Calendar.strftime(entry.timestamp, "%H:%M:%S")
    IO.puts(IO.ANSI.cyan() <> "#{time} #{entry.formatted}" <> IO.ANSI.reset())
  end

  def print_profile({name, %{role: role, opts: opts}}) do
    model = Keyword.get(opts, :model, "default")
    print_info("#{inspect(name)}: #{role || "(no role)"} [#{model}]")
  end

  def print_work_item(item) do
    status_color =
      case item.status do
        :done -> IO.ANSI.green()
        :failed -> IO.ANSI.red()
        :in_progress -> IO.ANSI.yellow()
        :ready -> IO.ANSI.cyan()
        :blocked -> IO.ANSI.light_black()
        _ -> ""
      end

    claimed = if item.claimed_by, do: " (#{item.claimed_by})", else: ""
    deps = if item.depends_on != [], do: " deps: #{inspect(item.depends_on)}", else: ""
    elapsed = format_elapsed(item)

    IO.puts(
      "  #{status_color}[#{item.status}]#{IO.ANSI.reset()} " <>
        "#{inspect(item.id)} - #{item.title}" <>
        " [#{item.type}]#{claimed}#{elapsed}#{deps}"
    )
  end

  def format_elapsed(%{status: :in_progress, started_at: started_at}) when started_at != nil do
    " #{elapsed_since(started_at)}"
  end

  def format_elapsed(%{status: :claimed, claimed_at: claimed_at}) when claimed_at != nil do
    " #{elapsed_since(claimed_at)}"
  end

  def format_elapsed(%{status: :done, started_at: started_at, completed_at: completed_at})
      when started_at != nil and completed_at != nil do
    seconds = DateTime.diff(completed_at, started_at)
    " (took #{format_duration(seconds)})"
  end

  def format_elapsed(_), do: ""

  defp elapsed_since(start) do
    seconds = DateTime.diff(DateTime.utc_now(), start)
    "(#{format_duration(seconds)} ago)"
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) when seconds < 3600,
    do: "#{div(seconds, 60)}m#{rem(seconds, 60)}s"

  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    mins = div(rem(seconds, 3600), 60)
    "#{hours}h#{mins}m"
  end

  def print_worker_info(info) do
    current = if info.current_item, do: " (working on #{inspect(info.current_item)})", else: ""

    print_info(
      "#{inspect(info.agent_name)}: #{info.work_type}, #{info.claims_completed} completed#{current}"
    )
  end

  def print_schedule_info(info) do
    last =
      if info.last_run_at,
        do: Calendar.strftime(info.last_run_at, "%H:%M:%S"),
        else: "never"

    print_info(
      "#{inspect(info.agent)}: every #{format_interval(info.interval)}, #{info.run_count} runs, last: #{last}"
    )
  end

  def format_interval(ms) when ms >= 3_600_000, do: "#{div(ms, 3_600_000)}h"
  def format_interval(ms) when ms >= 60_000, do: "#{div(ms, 60_000)}m"
  def format_interval(ms) when ms >= 1_000, do: "#{div(ms, 1_000)}s"
  def format_interval(ms), do: "#{ms}ms"

  def print_turn({turn, i}) do
    cost_str = if turn.cost_usd, do: " (#{format_cost(turn.cost_usd)})", else: ""
    error_str = if turn.is_error, do: " [error]", else: ""

    IO.puts(IO.ANSI.cyan() <> "--- Turn #{i}#{cost_str}#{error_str} ---" <> IO.ANSI.reset())
    IO.puts(turn.result)
    IO.puts("")
  end

  def print_table(header, rows) do
    all = [header | rows]

    widths =
      0..(tuple_size(header) - 1)
      |> Enum.map(fn i ->
        all |> Enum.map(fn row -> String.length(elem(row, i)) end) |> Enum.max()
      end)

    fmt_row = fn row ->
      0..(tuple_size(row) - 1)
      |> Enum.map_join(" | ", fn i -> String.pad_trailing(elem(row, i), Enum.at(widths, i)) end)
    end

    separator = Enum.map_join(widths, "-+-", &String.duplicate("-", &1))

    IO.puts(fmt_row.(header))
    IO.puts(separator)
    Enum.each(rows, fn row -> IO.puts(fmt_row.(row)) end)
  end
end
