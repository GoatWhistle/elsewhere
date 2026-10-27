require "active_record/tasks/database_tasks"

ActiveRecord::Tasks::DatabaseTasks.structure_dump_flags = {
  postgresql: %w[--clean --if-exists]
}
