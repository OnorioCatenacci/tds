defmodule Tds.Messages do
  import Record, only: [defrecord: 2]
  import Tds.Utils
  import Tds.Tokens, only: [decode_tokens: 2]

  alias Tds.Types

  require Logger
  require Bitwise

  defrecord :msg_prelogin, [:params]
  defrecord :msg_login, [:params]
  defrecord :msg_login_ack, [:type, :data]
  defrecord :msg_ready, [:status]
  defrecord :msg_sql, [:query]
  defrecord :msg_sql_result, [:columns, :rows, :done]
  defrecord :msg_sql_empty, []
  defrecord :msg_rpc, [:proc, :query, :params]
  defrecord :msg_error, [:e]

  ## TDS Versions
  @tds_ver_70     0x70000000
  @tds_ver_71     0x71000000
  @tds_ver_71rev1 0x71000001
  @tds_ver_72     0x72090002
  @tds_ver_73A    0x730A0003
  @tds_ver_73     @tds_ver_73A
  @tds_ver_73B    0x730B0003
  @tds_ver_74     0x74000004

  ## Microsoft Stored Procedures
  @tds_sp_cursor 1
  @tds_sp_cursoropen 2
  @tds_sp_cursorprepare 3
  @tds_sp_cursorexecute 4
  @tds_sp_cursorprepexec 5
  @tds_sp_cursorunprepare 6
  @tds_sp_cursorfetch 7
  @tds_sp_cursoroption 8
  @tds_sp_cursorclose 9
  @tds_sp_executesql 10
  @tds_sp_prepare 11
  @tds_sp_execute 12
  @tds_sp_prepexec 13
  @tds_sp_prepexecrpc 14
  @tds_sp_unprepare 15

  # Parameter Flags
  @fByRefValue 1
  @fDefaultValue 2

  ## Packet Types
  @tds_pack_sqlbatch    1
  @tds_pack_rpcRequest  3
  @tds_pack_reply       4
  @tds_pack_cancel      6
  @tds_pack_bulkloadbcp 7
  @tds_pack_transmgrreq 14
  @tds_pack_normal      15
  @tds_pack_login7      16
  @tds_pack_sspimessage 17
  @tds_pack_prelogin    18

  ## Prelogin Fields
  # http://msdn.microsoft.com/en-us/library/dd357559.aspx
  @tds_prelogin_version     0
  @tds_prelogin_encryption  1
  @tds_prelogin_instopt     2
  @tds_prelogin_threadid    3
  @tds_prelogin_mars        4
  @tds_prelogin_traceid     5
  @tds_prelogin_terminator  0xFF




  ## Parsers

  def parse(:login, @tds_pack_reply, _header, tail) do
    msg_login_ack(type: 4, data: tail)
  end

  def parse(:executing, @tds_pack_reply, _header, tail) do
    tokens = []
    case decode_tokens(tail, tokens) do
      [error: error] ->
        msg_error(e: error)
      tokens ->
        msg_sql_result(columns: tokens[:columns], rows: tokens[:rows], done: tokens[:done])
    end
  end

  

  ## Encoders

  def encode_msg(msg) do
    encode(msg)
  end

  defp encode(msg_prelogin(params: _params)) do
    version_data = <<11, 0, 12, 56, 0, 0>>
    version_length = byte_size(version_data)
    version_offset = 0x06
    version = <<0x00, version_offset::size(16), version_length::size(16)>>
    terminator = <<0xFF>>
    prelogin_data = version_data
    data = version <> terminator <> prelogin_data
    encode_header(0x12, data)<>data
  end

  defp encode(msg_login(params: params)) do
    tds_version = <<0x04, 0x00, 0x00, 0x74>>
    message_size = <<0x00, 0x10, 0x00, 0x00>>
    client_prog_ver = <<0x04, 0x00, 0x00, 0x07>>
    client_pid = <<0x00, 0x10, 0x00, 0x00>>
    connection_id = <<0x00::size(32)>>
    option_flags_1 = <<0x00>>
    option_flags_2 = <<0x00>>
    type_flags = <<0x00>>
    option_flags_3 = <<0x00>>
    client_time_zone = <<0xE0, 0x01, 0x00, 0x00>>
    client_lcid = <<0x09, 0x04, 0x00, 0x00>>

    login_a = tds_version <> message_size <> client_prog_ver <> client_pid <> connection_id <>
      option_flags_1 <> option_flags_2 <> type_flags <> option_flags_3 <> client_time_zone <> client_lcid
    offset_start = byte_size(login_a) + 4
    username = params[:username]
    password = params[:password]

    username_ucs = to_little_ucs2(username)
    password_ucs = to_little_ucs2(password)

    password_ucs_xor = encode_tdspassword(password_ucs)
    #Before submitting a password from the client to the server,
    #for every byte in the password buffer starting with the position pointed to by IbPassword,
    #the client SHOULD first swap the four high bits with the four low bits and
    #then do a bit-XOR with 0xA5 (10100101).

    clt_int_name = "ODBC"
    clt_int_name_ucs = to_little_ucs2(clt_int_name)
    database = params[:database] || ""
    database_ucs = to_little_ucs2(database)

    login_data = username_ucs <> password_ucs_xor <> clt_int_name_ucs <> database_ucs
    #IO.inspect Utils.to_hex_string(login_data)

    curr_offset = offset_start + 58
    ibHostName = <<curr_offset::little-size(16)>>
    cchHostName = <<0::size(16)>>

    ibUserName = <<curr_offset::little-size(16)>>
    cchUserName = <<String.length(username)::little-size(16)>>
    curr_offset = curr_offset + byte_size(username_ucs)

    ibPassword = <<curr_offset::little-size(16)>>
    cchPassword = <<String.length(password)::little-size(16)>>
    curr_offset = curr_offset + byte_size(password_ucs)

    ibAppName = <<0::size(16)>>
    cchAppName = <<0::size(16)>>

    ibServerName = <<0::size(16)>>
    cchServerName = <<0::size(16)>>

    ibUnused = <<0::size(16)>>
    cbUnused = <<0::size(16)>>

    ibCltIntName = <<curr_offset::little-size(16)>>
    cchCltIntName = <<4::little-size(16)>>
    curr_offset = curr_offset + 4*2

    ibLanguage = <<0::size(16)>>
    cchLanguage = <<0::size(16)>>

    ibDatabase = <<curr_offset::little-size(16)>>
    if database == "" do
      cchDatabase = <<0xAC>>
    else
      cchDatabase = <<String.length(database)::little-size(16)>>
    end


    clientID = <<0::size(48)>>

    ibSSPI = <<0::size(16)>>
    cbSSPI = <<0::size(16)>>

    ibAtchDBFile = <<0::size(16)>>
    cchAtchDBFile = <<0::size(16)>>

    ibChangePassword = <<0::size(16)>>
    cchChangePassword = <<0::size(16)>>

    cbSSPILong = <<0::size(32)>>

    offset = ibHostName <> cchHostName <> ibUserName <> cchUserName <> ibPassword <> cchPassword <>
      ibAppName <> cchAppName <> ibServerName <> cchServerName <> ibUnused <> cbUnused <>
      ibCltIntName <> cchCltIntName <>
      ibLanguage <> cchLanguage <> ibDatabase <> cchDatabase <> clientID <> ibSSPI <> cbSSPI <>
      ibAtchDBFile <> cchAtchDBFile <> ibChangePassword <> cchChangePassword <> cbSSPILong

    #IO.inspect Utils.to_hex_string(offset)
    login7 =  login_a <> offset <> login_data
    #IO.inspect Utils.to_hex_string(login7)

    login7_len = byte_size(login7) + 4
    data = <<login7_len::little-size(32)>> <> login7
    header = encode_header(0x10, data)

    header <> data
  end

  defp encode(msg_sql(query: q)) do
    #Logger.debug "Msg SQL"
    #convert query to unicodestream
    q_ucs = to_little_ucs2(q)

    #Transaction Descriptor header
    header_type = <<2::little-size(2)-unit(8)>>
    transaction_descriptor = <<0::(8*8)>>
    outstanding_request_count = <<1::little-size(4)-unit(8)>>
    td_header = header_type <> transaction_descriptor <> outstanding_request_count
    td_header_len = byte_size(td_header) + 4
    td_header = <<td_header_len::little-size(4)-unit(8)>> <> td_header

    headers = td_header
    total_length = byte_size(headers) + 4
    all_headers = <<total_length::little-size(32)>> <> headers
    data = all_headers <> q_ucs
    header = encode_header(0x01, data)
    header <> data
  end

  defp encode(msg_rpc(proc: proc, params: params)) do
    #Transaction Descriptor header
    header_type = <<2::little-size(2)-unit(8)>>
    transaction_descriptor = <<0::(8*8)>>
    outstanding_request_count = <<1::little-size(4)-unit(8)>>
    td_header = header_type <> transaction_descriptor <> outstanding_request_count
    td_header_len = byte_size(td_header) + 4
    td_header = <<td_header_len::little-size(4)-unit(8)>> <> td_header

    headers = td_header
    total_length = byte_size(headers) + 4
    all_headers = <<total_length::little-size(32)>> <> headers

    data = all_headers <> encode_rpc(proc, params)
    #layout Data
    
    header = encode_header(0x03, data)
    pak = header <> data
    #Logger.debug "RPC #{Tds.Utils.to_hex_string pak}"
    pak
  end

  defp encode_rpc(:sp_executesql, params) do
    <<0xFF, 0xFF, @tds_sp_executesql::little-size(2)-unit(8), 0x00, 0x00>> <> encode_rpc_params(params, "")
  end

  # Finished processing params
  defp encode_rpc_params([], ret), do: ret 
  defp encode_rpc_params([%Tds.Parameter{} = param | tail], ret) do
    p = encode_rpc_param(param)
    encode_rpc_params(tail, ret <> p)
  end

  defp encode_rpc_param(%Tds.Parameter{name: name, value: value, direction: _direction} = param) do
    #Logger.debug "RPC Param name:#{name}, value:#{value}"

    p_name = to_little_ucs2(name)
    p_flags = param |> Tds.Parameter.option_flags
    
    {p_data_type, p_data_type_value} = Types.encode_data_type(value)
    p_meta_data = <<byte_size(p_name)>> <> to_little_ucs2(p_name) <> p_flags <> p_data_type_value
    p_len_data = Types.encode_data(p_data_type, value)
    p_meta_data <> p_len_data
  end

  defp encode_header(type, data) do
    status = 0x01
    length = byte_size(data) + 8
    message = 0x01
    <<
      type,
      status,
      length::size(16),
      0::size(16),
      message,
      0
    >>
  end

  defp encode_tdspassword(list) do
    #IO.inspect list
    for <<b::size(8) <- list>> do
      #IO.puts b
      <<x::size(4), y::size(4)>> = <<b>> #swap 4 bits
      <<c>> = <<y::size(4), x::size(4)>>
      #IO.puts c
      Bitwise.bxor(c, 0xA5)
    end
    |> Enum.map_join(&(<<&1>>)) #TODO UGLY!!!
  end

end
