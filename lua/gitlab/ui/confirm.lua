local M = {}

function M.ask(message, callback)
  vim.ui.select({ "No", "Yes" }, {
    prompt = message,
  }, function(choice)
    callback(choice == "Yes")
  end)
end

return M
