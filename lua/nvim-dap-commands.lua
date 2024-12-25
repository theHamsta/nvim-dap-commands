#! /usr/bin/env lua
--
-- nvim-dap-commands.lua
-- Copyright (C) 2024 stephan <stephan.seitz@fau.de>
--
-- Distributed under terms of the GPLv3 license.
--

---@param executables string[]
---@return string|nil
local function select_executable(executables)
  return vim.tbl_filter(function(c) ---@param c string
    return c ~= vim.NIL and vim.fn.executable(c) == 1
  end, executables)[1]
end

local python_adapter
local python_path = select_executable { --[["uv",]]
  "python3",
  "python",
}

-- from nvim-dap-python
if python_path == "uv" then
  python_adapter = {
    type = "executable",
    command = "uv",
    args = { "run", "--with", "debugpy", "python", "-m", "debugpy.adapter" },
    --enrich_config = enrich_config,
    options = {
      source_filetype = "python",
    },
  }
else
  python_adapter = {
    type = "executable",
    command = python_path,
    args = { "-m", "debugpy.adapter" },
    --enrich_config = enrich_config,
    options = {
      source_filetype = "python",
    },
  }
end

local ENV = {}
for k, v in pairs(vim.fn.environ()) do
  table.insert(ENV, string.format("%s=%s", k, v))
end

local M = {}
local defaults = {
  post_launch_commands = function()
    local dap = require "dap"
    dap.repl.open()
  end,
  debuggers = {
    gdb = {
      cmd = "DebugGdb",
      adapter = {
        type = "executable",
        attach = {
          pidProperty = "pid",
          pidSelect = "ask",
        },
        command = select_executable {
          "rust-gdb",
          "gdb",
        },
        args = {
          "--quiet",
          "-i",
          "dap",
        },
        name = "gdb",
        stopOnEntry = false,
        --initCommands = 'command script import "/home/stephan/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/lib/rustlib/etc/lldb_lookup.py"',
      },
      config = function(args)
        return {
          type = "rust",
          name = args[1],
          request = "launch",
          program = table.remove(args, 1),
          args = args,
          cwd = vim.fn.getcwd(),
          --initCommands = get_init_commands(),
        }
      end,
    },
    lldb = {
      cmd = "DebugLldb",
      adapter = {
        type = "executable",
        attach = {
          pidProperty = "pid",
          pidSelect = "ask",
        },
        command = select_executable {
          "lldb-dap-20",
          "lldb-dap-19",
          "lldb-vscode-18",
          "lldb-vscode-17",
          "lldb-vscode-16",
          "lldb-vscode-15",
          "lldb-vscode",
        },
        env = function()
          local variables = {
            LLDB_LAUNCH_FLAG_LAUNCH_IN_TTY = "YES",
          }
          for k, v in pairs(vim.fn.environ()) do
            table.insert(variables, string.format("%s=%s", k, v))
          end
          return variables
        end,
        name = "lldb",
        stopOnEntry = false,
        --initCommands = 'command script import "/home/stephan/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/lib/rustlib/etc/lldb_lookup.py"',
      },
      config = function(args)
        args = vim.tbl_map(function(arg)
          return vim.fn.expand(arg)
        end, args)
        if args and #args > 0 then
          return {
            type = "rust",
            name = args[1],
            request = "launch",
            program = table.remove(args, 1),
            env = ENV,
            args = args,
            cwd = vim.fn.getcwd(),
            environment = {},
            stopOnEntry = false,
            externalConsole = true,
            expressions = "python",
            --initCommands = get_init_commands(),
          }
        end
      end,
    },
    debugpy = {
      cmd = "Debugpy",
      adapter = python_adapter,
      config = function(args)
        return {
          type = "python",
          name = args[1],
          console = "integratedTerminal",
          justMyCode = true,
          request = "launch",
          program = table.remove(args, 1),
          args = args,
          --pythonPath = function()
          --return "/usr/bin/python3"
          --end
        }
      end,
    },
  },
}

function M.setup(opts)
  opts = vim.tbl_deep_extend("keep", opts, defaults)
  for k, v in pairs(opts.debuggers) do
    if v.cmd then
      vim.api.nvim_create_user_command(v.cmd, function(t)
        local dap = require "dap"
        local config
        if #t.fargs == 0 then
          if not v.last_config then
            vim.notify(
              "Please provide arguments to " .. v.cmd .. " (the program with arguments that you want to launch)",
              vim.log.levels.ERROR
            )
            return
          end
          config = v.last_config
        else
          config = v.config(t.fargs)
        end
        if type(config) == "string" then
          vim.notify("Could not launch debug adapter: " .. config, vim.log.levels.ERROR)
          return
        end
        if config then
          dap.launch(v.adapter, config, {})
          v.last_config = config
        else
          vim.notify(
            "Could not launch debug adapter " .. k .. ": user provided config function returned nil",
            vim.log.levels.ERROR
          )
        end
        if opts.post_launch_commands then
          opts.post_launch_commands(t)
        end
      end, {
        complete = "file",
        nargs = "*",
      })
    end
  end
end

return M
