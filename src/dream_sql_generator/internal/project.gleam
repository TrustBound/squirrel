//// A set of utilities to work within a Gleam project.
////

import dream_sql_generator/internal/error.{
  type Error, CannotParseGleamToml, CannotReadFile, InvalidClientModule,
  InvalidClientModuleType,
}
import dream_sql_generator/internal/gleam
import filepath
import gleam/list
import gleam/result
import gleam/string
import simplifile
import tom

/// Returns the project's name, read from the `gleam.toml` file.
///
pub fn name() -> Result(String, Nil) {
  let configuration_path = filepath.join(root(), "gleam.toml")

  use configuration <- try_nil(simplifile.read(configuration_path))
  use toml <- try_nil(tom.parse(configuration))
  use name <- try_nil(tom.get_string(toml, ["name"]))
  Ok(name)
}

/// The Gleam module that the generated code uses to run queries. It is `pog`
/// by default, and a project can change it with the `client_module` setting in
/// the `[tools.dream_sql_generator]` table of its `gleam.toml`:
///
/// ```toml
/// [tools.dream_sql_generator]
/// client_module = "dream_postgres_client"
/// ```
///
/// A `ClientModule` can only be built from a valid Gleam module name.
///
pub opaque type ClientModule {
  ClientModule(name: String)
}

const default_client_module = "pog"

/// Returns the name of the client module, for example `"dream_postgres_client"`.
///
pub fn client_module_name(client: ClientModule) -> String {
  client.name
}

/// Reads the client module from the project's `gleam.toml` file.
///
pub fn client_module() -> Result(ClientModule, Error) {
  let configuration_path = filepath.join(root(), "gleam.toml")

  use configuration <- result.try(
    simplifile.read(configuration_path)
    |> result.map_error(CannotReadFile(configuration_path, _)),
  )
  client_module_from_toml(configuration_path, configuration)
}

/// Reads the client module from the content of a `gleam.toml` file. The `file`
/// is only used in the error messages.
///
pub fn client_module_from_toml(
  file: String,
  configuration: String,
) -> Result(ClientModule, Error) {
  use toml <- result.try(
    tom.parse(configuration)
    |> result.replace_error(CannotParseGleamToml(file)),
  )

  case tom.get_string(toml, ["tools", "dream_sql_generator", "client_module"]) {
    Error(tom.NotFound(_)) -> Ok(ClientModule(default_client_module))
    Error(tom.WrongType(key:, expected:, got:)) ->
      Error(InvalidClientModuleType(
        file:,
        key: string.join(key, with: "."),
        expected:,
        got:,
      ))
    Ok(name) ->
      case is_module_name(name) {
        True -> Ok(ClientModule(name))
        False -> Error(InvalidClientModule(file:, value: name))
      }
  }
}

/// A module name is one or more lowercase names separated by slashes, for
/// example `dream_postgres_client` or `my_app/database`.
///
fn is_module_name(name: String) -> Bool {
  use segment <- list.all(string.split(name, on: "/"))
  result.is_ok(gleam.value_identifier(segment))
}

fn try_nil(
  result: Result(a, b),
  then do: fn(a) -> Result(c, Nil),
) -> Result(c, Nil) {
  result.try(result.replace_error(result, Nil), do)
}

/// Finds the path of the project's `src` directory.
/// This recursively walks up from the current directory until it finds a
/// `gleam.toml` and builds it from there.
///
pub fn src() -> String {
  filepath.join(root(), "src")
}

/// Finds the path of the project's `test` directory.
/// This recursively walks up from the current directory until it finds a
/// `gleam.toml` and builds it from there.
///
pub fn test_() -> String {
  filepath.join(root(), "test")
}

/// Finds the path of the project's `dev` directory.
/// This recursively walks up from the current directory until it finds a
/// `gleam.toml` and builds it from there.
///
pub fn dev() -> String {
  filepath.join(root(), "dev")
}

/// Finds the path leading to the project's root folder. This recursively walks
/// up from the current directory until it finds a `gleam.toml`.
///
fn root() -> String {
  find_root(".")
}

fn find_root(path: String) -> String {
  let toml = filepath.join(path, "gleam.toml")

  case simplifile.is_file(toml) {
    Ok(False) | Error(_) -> find_root(filepath.join("..", path))
    Ok(True) -> path
  }
}
