defmodule AgentWorkshop.Backend do
  @moduledoc """
  Behaviour for LLM CLI backends.

  Workshop uses this behaviour to communicate with agents. Each backend
  wraps a specific CLI tool (Claude, Codex, etc.) and provides a uniform
  interface for session management and message passing.

  ## Implementing a backend

      defmodule MyApp.ClaudeBackend do
        @behaviour AgentWorkshop.Backend

        @impl true
        def start_session(config, opts) do
          # Start a session process, return {:ok, pid}
        end

        @impl true
        def send_message(server, prompt, opts) do
          # Send a message, return {:ok, result} or {:error, reason}
        end

        # ... other callbacks
      end

  ## Result map

  The `result` type is a map with these keys:

    * `:result` - response text (string)
    * `:session_id` - session identifier for continuation (string or nil)
    * `:cost_usd` - cost in USD (float or nil)
    * `:is_error` - whether this is an error result (boolean)
    * `:duration_ms` - execution time (integer or nil)
    * `:num_turns` - number of turns (integer or nil)
  """

  @type result :: %{
          result: String.t(),
          session_id: String.t() | nil,
          cost_usd: float() | nil,
          is_error: boolean(),
          duration_ms: non_neg_integer() | nil,
          num_turns: non_neg_integer() | nil
        }

  @type server :: GenServer.server()
  @type config :: term()

  @doc """
  Start a new session process.

  Returns `{:ok, pid}` where pid is a process that can receive
  `send_message/3` calls. The process should be linkable for
  supervision.
  """
  @callback start_session(config(), keyword()) :: {:ok, pid()} | {:error, term()}

  @doc """
  Send a message to a session. Blocks until the response is ready.
  """
  @callback send_message(server(), String.t(), keyword()) ::
              {:ok, result()} | {:error, term()}

  @doc """
  Get the session ID (if established).
  """
  @callback session_id(server()) :: String.t() | nil

  @doc """
  Get the full conversation history.
  """
  @callback history(server()) :: [result()]

  @doc """
  Get the total cost across all turns.
  """
  @callback total_cost(server()) :: float()

  @doc """
  Get the number of completed turns.
  """
  @callback turn_count(server()) :: non_neg_integer()

  @doc """
  Get the last result, if any.
  """
  @callback last_result(server()) :: result() | nil

  @doc """
  Stop the session process.
  """
  @callback stop_session(server()) :: :ok
end
