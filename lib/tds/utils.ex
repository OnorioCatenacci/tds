defmodule Tds.Utils do
  require Logger
  def to_hex_list(x) when is_list(x) do
    Enum.map x, &( Base.encode16(<<&1>>))
  end

  def to_hex_list(x) when is_binary(x)  do
    :erlang.binary_to_list(x)
      |> to_hex_list
  end

  def to_hex_string(x) when is_binary(x) do
    to_hex_list(x)
      |> to_hex_string
  end

  def to_hex_string(x) when is_list(x) do
    Enum.join x, " "
  end

  def to_little_ucs2(s) do
    to_char_list(s) |> Enum.map_join(&(<<&1::little-size(16)>>))
  end

  def ucs2_to_utf(s) do
    to_char_list(s) |> Enum.reject(&(&1 == 0)) |> to_string
  end

  def to_boolean(<<1>>) do
    true
  end

  def to_boolean(<<0>>) do
    false
  end

  def collation_to_charset(<<collation::binary>>) do
    
  end

  def error(error, s) do
    if reply(error, s) do
      Logger.debug "Error Normal"
      {:stop, :normal, s}
    else
      Logger.debug "Error Exiting"
      {:stop, error, s}
    end
  end

  def reply(reply, %{queue: queue}) do
    case :queue.out(queue) do
      {{:value, {_command, from, _timer}}, _queue} ->
        GenServer.reply(from, reply)
        true
      {:empty, _queue} ->
        false
    end
  end

  def reply(reply, {_, _} = from) do
    GenServer.reply(from, reply)
    true
  end

  def pow10(num,0), do: num
  def pow10(num,pow) when pow > 0 do
    pow10(10*num, pow - 1)
  end

  def pow10(num,pow) when pow < 0 do
    pow10(num/10, pow + 1)
  end
end
