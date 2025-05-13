defmodule FileTransformerWeb.PageController do
  use FileTransformerWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def start(conn, params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :start, upload_success: params["upload_success"] == "true")
  end


  alias Elixlsx.{Workbook, Sheet}
  require Logger

  # rows = Xlsxir.get_list(table_id):
  # projects = ProjectSheetParser.parse(rows)

  def upload(conn, %{"file" => %Plug.Upload{path: path, filename: filename}}) do
    sheet_index = 1 # for the Fee and Projection Report
    {:ok, table_id} = Xlsxir.multi_extract(path, sheet_index)


    # Basic, first match
    matches =
      Xlsxir.get_list(table_id)
      |> Enum.filter(fn [first | _rest] ->
        is_binary(first) and String.contains?(first, "Project Number")
      end)


    # Active matches
    rows2 = Xlsxir.get_list(table_id)
    projects2 = ProjectSheetParser.parse(rows2)
    projects2 |> IO.inspect


    project_rows = projects2
      |> Enum.filter(fn project -> not is_nil(project.footer) end)
      |> Enum.map(&ProjectFormatter.summarize_project/1)
      |> Enum.flat_map(& &1)

    # Add header row
    rows = project_rows

    # Create new XLSX
    sheet = %Elixlsx.Sheet{name: "Matches", rows: rows}
    workbook = %Elixlsx.Workbook{sheets: [sheet]}
    output_file = "/tmp/matches_#{:os.system_time(:millisecond)}.xlsx"
    Elixlsx.write_to(workbook, output_file)

    send_download(conn,
      {:file, output_file},
      filename: "matches.xlsx",
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
  end
end


defmodule ProjectParser do
  def parse_line("Project Number: " <> rest) do
    case Regex.run(~r/^(\d+)\.(\d+)\s+(.+)$/, rest) do
      [_, project_id, subproject_id, name] ->
        %{
          project_id: project_id,
          subproject_id: subproject_id,
          name: String.trim(name)
        }

      _ ->
        :error
    end
  end

  def parse_line(_), do: :error
end


defmodule NameParser do
  def initials(name) do

    case name do
      nil ->
        ""

      "" ->
        ""

      name ->
        name
          |> String.split(~r/,\s*|\s+/) # split on comma or space
          |> Enum.map(&String.first/1)
          |> Enum.reverse()
          |> Enum.join()
          |> String.upcase()
    end
  end
end


defmodule ProjectFormatter do
  @project_rx ~r/^Project Number: (\d+)\.(\d+)\s+(.+)$/

  def first_n_rows_with_padding(rows, row_limit) do
    trimmed = Enum.take(rows, row_limit)
    missing = row_limit - length(trimmed)
    padding = List.duplicate([], missing)
    trimmed ++ padding
  end

  # Returns one or more rows.
  def summarize_project(%{header: [line | _], body: body, footer: footer}) do

    project_name = if line do
      %{
        name: name,
        project_id: project_id,
        subproject_id: subproject_id,
      } = ProjectParser.parse_line(line)
      name
    else
      nil
    end

    project_id = if line do
      %{
        name: name,
        project_id: project_id,
        subproject_id: subproject_id,
      } = ProjectParser.parse_line(line)
      project_id
    else
      nil
    end

    subproject_id = if line do
      %{
        name: name,
        project_id: project_id,
        subproject_id: subproject_id,
      } = ProjectParser.parse_line(line)
      subproject_id
    else
      nil
    end
    pm = if footer, do: Enum.at(footer, 6), else: nil

    body_rows = Enum.map(body, fn row ->
      [project_name_and_code, _, _, _, _, name, project_manager, phase, budget, _, status, _, project_type, _, _, _] = row

      [
        "",
        "",
        "",
        project_name_and_code,
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        budget,
        project_type
      ]
    end)
    |> first_n_rows_with_padding(9)

    rows = if pm do
      [
        [
          "#{project_id}.#{subproject_id}",
          project_name,
          pm,
        ]
      ]
    else
      nil
    end

    rows ++ body_rows
  end
end



defmodule ProjectSheetParser do
  @header_rx ~r/^Project Number: \d+\.\d+ .+/
  @footer_rx ~r/Total/

  def parse(rows) when is_list(rows) do
    do_parse(rows, [], [])
  end

  defp do_parse([], current, acc) do
    case current do
      [] -> acc
      _ -> Enum.reverse([group_project(current) | acc])
    end
  end

  defp do_parse([row | rest], current, acc) do
    cond do
      match_header?(row) and current == [] ->
        do_parse(rest, [row], acc)

      match_header?(row) ->
        do_parse(rest, [row], [group_project(current) | acc])

      true ->
        do_parse(rest, [row | current], acc)
    end
  end

  defp match_header?([cell | _]), do: is_binary(cell) and Regex.match?(@header_rx, cell)
  defp match_footer?([cell | _]), do: is_binary(cell) and Regex.match?(@footer_rx, cell)

  defp group_project(rows) do
    rows = Enum.reverse(rows)
    {header, rest} = List.pop_at(rows, 0)

    case Enum.split(rest, -1) do
      {body, [last]} ->
        if match_footer?(last) do
          %{
            header: header,
            body: Enum.reverse(body) |> Enum.reverse,
            footer: last
          }
        else
          %{
            header: header,
            body: Enum.reverse(rest),
            footer: nil
          }
        end

      _ ->
        %{
          header: header,
          body: Enum.reverse(rest),
          footer: nil
        }
    end
  end

end
