defmodule Memcachir do
  @moduledoc """
  Module with a friendly API for memcached servers.

  It provides connection pooling, and cluster support.

  ## Example

      {:ok} = Memcachir.set("hello", "world")
      {:ok, "world"} = Memcachir.get("hello")

  """
  use Application

  alias Memcachir.Util

  @doc """
  Starts application.
  """
  def start(_type, _args) do
    servers = get_servers()

    # Build the hashring
    {:ok, _pid} = HashRing.Managed.new(:memcachir_ring)
    Enum.each(servers, fn({host, port}) ->
      :ok = HashRing.Managed.add_node(
              :memcachir_ring, Util.host_to_atom(host, port))
    end)

    options =
      Application.get_all_env(:memcachir)
      |> Keyword.put(:servers, servers)
    pool_options = Application.get_env(:memcachir, :pool, [])

    Memcachir.Supervisor.start_link(options, pool_options)
  end

  @doc """
  Gets the value associated with the key. Returns `{:error, "Key not found"}`
  if the given key doesn't exist.
  """
  def get(key, opts \\ []) do
    node = key_to_node(key)
    execute(&Memcache.get/3, node, [key, opts])
  end

  @doc """
  Sets the key to value.
  """
  def set(key, value, opts \\ []) do
    node = key_to_node(key)
    execute(&Memcache.set/4, node, [key, value, opts])
  end

  @doc """
  Removes the item with the specified key. Returns `{:ok, :deleted}`
  """
  def delete(key) do
    node = key_to_node(key)
    execute(&Memcache.delete/2, node, [key])
  end

  @doc """
  """
  def version() do
    nodes = HashRing.Managed.nodes(:memcachir_ring)
    execute(&Memcache.version/1, nodes)
  end

  @doc """
  Removes all the items from the server. Returns `{:ok}`.
  """
  def flush(opts \\ []) do
    nodes = HashRing.Managed.nodes(:memcachir_ring)
    execute(&Memcache.flush/2, nodes, [opts])
  end

  def execute(fun, nodes, args \\ [])
  def execute(fun, [node | nodes], args) do
    if length(nodes) > 0 do
      execute(fun, nodes, args)
    end
    execute(fun, node, args)
  end
  def execute(fun, node, args) do
    :poolboy.transaction(node, fn(worker) ->
      apply(fun, [worker | args])
    end)
  end

  defp key_to_node(key) do
    HashRing.Managed.key_to_node(:memcachir_ring, key)
  end

  # Returns a list like [{host1, port1}, {host2, port2}, ...]
  # from the configured hosts parameter or reading it from elasticache
  defp get_servers() do
    case Application.get_env(:memcachir, :elasticache) do
      nil ->
        Util.read_config_hosts(Application.get_env(:memcachir, :hosts))
      elasticache ->
        Util.read_config_elasticache(elasticache)
    end
  end

end
