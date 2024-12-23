extends Node

const GITHUB_API_URL = "https://api.github.com"
var OWNER = "FNF-CNE-Devs"
var REPO = "CodenameEngine"
const MAX_WORKFLOWS = 100
const GITHUB_TOKEN = ""
const TEMP_DIR = "temp"
var DOWNLOAD_DIR = "downloads/" + REPO + "-" + OWNER
const API_DOWNLOAD_URL = "https://github.com/%s/%s/archive/%s.zip"
const ARTIFACTS_API_URL = GITHUB_API_URL + "/repos/%s/%s/actions/runs/%s/artifacts"

@onready var commit_name = $"../Git Text Group/git-commit-name"
@onready var workflow_name = $"../Git Text Group/git-workflow-name"
@onready var trigger_commit = $"../Git Text Group/git-trigger-name"
@onready var author_name = $"../Git Text Group/git-author-name2"
@onready var commit_hash = $"../Git Text Group/git-author-name3"
@onready var page_counter = $"../Git Text Group/page-counter"
@onready var left_text = $"../Download Text Group/dl text"
@onready var middle_text = $"../Download Text Group/dl text2"
@onready var right_text = $"../Download Text Group/dl text3"

var http_request: HTTPRequest
var artifact_request: HTTPRequest
var download_request: HTTPRequest
var current_workflow_index = 0
var workflow_runs = []
var download_start_time: float = 0.0
var download_size: float = 0.0
var downloaded_bytes: float = 0.0
var is_downloading: bool = false
var total_bytes: float = 0.0
var download_retries: int = 0
const MAX_RETRIES = 1
var current_bytes = 0
var download_timer: Timer = null
var current_repo_index = 0
var repos = [
	{"owner": "FNF-CNE-Devs", "repo": "CodenameEngine"}  # Default repo
]
var is_typing_repo = false
var typed_repo = ""

func _ready():
	http_request = HTTPRequest.new()
	artifact_request = HTTPRequest.new()
	download_request = HTTPRequest.new()
	download_request.use_threads = true
	download_request.download_chunk_size = 65536
	download_request.body_size_limit = -1
	download_request.timeout = 0
	download_request.max_redirects = 5
	
	add_child(http_request)
	add_child(artifact_request)
	add_child(download_request)
	
	http_request.request_completed.connect(_on_request_completed)
	artifact_request.request_completed.connect(_on_artifact_request_completed)
	download_request.request_completed.connect(_on_download_completed)
	
	fetch_workflow_info()
	update_page_counter()

func fetch_workflow_info():
	var headers = []
	if GITHUB_TOKEN != "":
		headers = ["Authorization: Bearer " + GITHUB_TOKEN]
	
	var endpoint = "/repos/%s/%s/actions/runs?per_page=%d" % [OWNER, REPO, MAX_WORKFLOWS]
	var url = GITHUB_API_URL + endpoint
	
	var error = http_request.request(url, headers)
	if error != OK:
		print("An error occurred in the HTTP request.")

func _on_request_completed(result, response_code, headers, body):
	if response_code != 200:
		print("Failed to get workflow information")
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null or not json.has("workflow_runs"):
		print("No workflow runs found")
		return
	
	workflow_runs = json.workflow_runs
	update_workflow_display()

func get_first_line(text: String) -> String:
	var lines = text.split("\n")
	return lines[0].strip_edges()

func truncate_text(text: String, max_length: int) -> String:
	if text.length() <= max_length:
		return text
	return text.substr(0, max_length - 3) + "..."

func update_workflow_display():
	if workflow_runs.size() == 0:
		return
	
	var current_run = workflow_runs[current_workflow_index]
	
	var commit_message = get_first_line(current_run.head_commit.message)
	
	var truncated_commit = truncate_text(commit_message, 33)
	var truncated_workflow = truncate_text(current_run.name, 30)
	var truncated_author = truncate_text(current_run.actor.login, 20)
	
	commit_name.text = truncated_commit
	workflow_name.text = "Workflow: " + truncated_workflow
	trigger_commit.text = "Triggering Commit: " + commit_message
	author_name.text = "Author: " + truncated_author
	commit_hash.text = "Commit Hash: " + current_run.head_sha.substr(0, 7)
	
	update_download_info()
	update_page_counter()

func update_page_counter():
	var total = workflow_runs.size()
	var current = current_workflow_index + 1 if total > 0 else 0
	page_counter.text = "%d/%d" % [current, total]

func _input(event):
	if is_typing_repo:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ENTER:
				var parts = typed_repo.split("/")
				if parts.size() == 2:
					repos.append({"owner": parts[0], "repo": parts[1]})
					current_repo_index = repos.size() - 1
					OWNER = parts[0]
					REPO = parts[1]
					fetch_workflow_info()
				
				is_typing_repo = false
				typed_repo = ""
				
			elif event.keycode == KEY_ESCAPE:
				is_typing_repo = false
				typed_repo = ""
				
			elif event.keycode == KEY_BACKSPACE:
				typed_repo = typed_repo.substr(0, max(0, typed_repo.length() - 1))
				
			elif event.is_pressed() and not event.echo:
				var char = char(event.unicode)
				if char.length() > 0:
					typed_repo += char
					
			if is_typing_repo:
				middle_text.text = "Enter repo: " + typed_repo
				
	else:
		if event.is_action_pressed("ui_left"):
			change_workflow(-1)
		elif event.is_action_pressed("ui_right"):
			change_workflow(1)
		elif event.is_action_pressed("ui_accept"):
			download_current_workflow()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_S:
			is_typing_repo = true
			typed_repo = ""
			middle_text.text = "Enter repo: "

func change_workflow(direction):
	if workflow_runs.size() == 0:
		return
	
	current_workflow_index = (current_workflow_index + direction) % workflow_runs.size()
	if current_workflow_index < 0:
		current_workflow_index = workflow_runs.size() - 1
	
	update_workflow_display()

func download_current_workflow():
	if workflow_runs.size() == 0 or is_downloading:
		return
		
	var current_run = workflow_runs[current_workflow_index]
	if current_run.head_sha == "Loading..." or current_run.head_sha == "N/A":
		return
		
	is_downloading = true
	download_start_time = Time.get_unix_time_from_system()
	
	var artifacts_url = "https://api.github.com/repos/%s/%s/actions/runs/%s/artifacts" % [
		OWNER,
		REPO,
		current_run.id
	]
	
	var headers = [
		"Accept: application/vnd.github+json",
		"User-Agent: GodotEngine"
	]
	
	right_text.text = "Fetching artifacts..."
	var error = artifact_request.request(artifacts_url, headers)
	if error != OK:
		print("Failed to fetch artifacts: ", error_string(error))
		_handle_download_error("Failed to fetch artifacts!")
		return

func _on_artifact_request_completed(result, response_code, headers, body):
	if response_code != 200:
		print("Failed to get artifacts")
		right_text.text = "Failed! No artifacts"
		is_downloading = false
		return
		
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null or not json.has("artifacts") or json.artifacts.size() == 0:
		print("No artifacts found")
		right_text.text = "Failed! No artifacts"
		is_downloading = false
		return
		
	var artifact = json.artifacts[0]
	var encoded_name = artifact.name.uri_encode()
	download_size = artifact.size_in_bytes
	downloaded_bytes = 0
	
	var download_url = "https://nightly.link/%s/%s/actions/runs/%s/%s.zip" % [
		OWNER,
		REPO,
		workflow_runs[current_workflow_index].id,
		encoded_name
	]
	print("Starting artifact download from: ", download_url)
	
	download_request.use_threads = true
	download_request.download_chunk_size = 65536
		
	download_timer = Timer.new()
	add_child(download_timer)
	download_timer.timeout.connect(func():
		var elapsed = int(Time.get_unix_time_from_system() - download_start_time)
		var current_bytes = download_request.get_downloaded_bytes()
		
		if download_size > 0:
			var progress = (float(current_bytes) / float(download_size)) * 100.0
			right_text.text = "%.2f%% | %ds" % [progress, elapsed]
		else:
			right_text.text = "Downloading... | %ds" % elapsed
	)
	download_timer.start(0.1)
	
	var download_headers = [
		"Accept: application/zip",
		"User-Agent: GodotEngine"
	]
	
	var error = download_request.request(download_url, download_headers)
	if error != OK:
		print("Failed to start download")
		right_text.text = "Failed to start download!"
		is_downloading = false

func _on_download_completed(result, response_code, headers, body):
	for header in headers:
		if header.begins_with("Content-Length:"):
			total_bytes = header.split(" ")[1].to_int()
			break
	
	current_bytes = body.size() if body != null else 0
	
	print("Download completed with result: ", result)
	
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_download_error("Error: %d (%s)" % [result, error_string(result)])
		return
	
	if response_code != 200:
		right_text.text = "Failed! HTTP %d" % response_code
		print("Failed to download. Response code: ", response_code)
		return
	
	if body.size() == 0:
		right_text.text = "Failed! Empty download"
		print("Download failed: Empty body")
		return
	
	var base_dir = OS.get_executable_path().get_base_dir()
	var dir = DirAccess.open(base_dir)
	
	if not dir.dir_exists(TEMP_DIR):
		dir.make_dir(TEMP_DIR)
	
	var zip_path = base_dir.path_join(TEMP_DIR).path_join("download.zip")
	print("Saving downloaded file to: ", zip_path)
	
	var zip_file = FileAccess.open(zip_path, FileAccess.WRITE)
	if zip_file == null:
		right_text.text = "Failed to write file!"
		print("Failed to create zip file")
		return
	
	zip_file.store_buffer(body)
	zip_file.close()
	print("File saved successfully, size: ", body.size(), " bytes")
	
	var target_dir = base_dir.path_join(DOWNLOAD_DIR)
	if not dir.dir_exists(DOWNLOAD_DIR):
		dir.make_dir(DOWNLOAD_DIR)
	
	print("Extracting files to: ", target_dir)
	var zip_reader = ZIPReader.new()
	var error = zip_reader.open(zip_path)
	
	if error != OK:
		right_text.text = "Failed to open zip!"
		print("Failed to open zip file, error: ", error)
		return
	
	var files = zip_reader.get_files()
	print("Found ", files.size(), " files in archive")
	
	var extracted_count = 0
	var total_files = files.size()
	
	for file_name in files:
		extracted_count += 1
		var progress = int((float(extracted_count) / total_files) * 100)
		right_text.text = "Extracting... %d%%" % progress
		
		var content = zip_reader.read_file(file_name)
		var target_path = target_dir.path_join(file_name)
		
		var file_dir = target_path.get_base_dir()
		if not dir.dir_exists(file_dir):
			dir.make_dir_recursive(file_dir)
		
		var out_file = FileAccess.open(target_path, FileAccess.WRITE)
		if out_file != null:
			out_file.store_buffer(content)
			out_file.close()
	
	zip_reader.close()
	cleanup_temp()
	
	var elapsed = int(Time.get_unix_time_from_system() - download_start_time)
	right_text.text = "Done! | %ds" % elapsed
	
	if download_timer:
		download_timer.stop()
		download_timer.queue_free()
		download_timer = null

func _on_download_progress(downloaded: float, total: float):
	print("Download progress - Downloaded: %d, Total: %d" % [downloaded, total])
	downloaded_bytes = downloaded
	
	if download_size > 0:
		var progress = (downloaded_bytes / download_size) * 100
		var elapsed = int(Time.get_unix_time_from_system() - download_start_time)
		right_text.text = "%.2f%% | %ds" % [progress, elapsed]

func cleanup_temp():
	var base_dir = OS.get_executable_path().get_base_dir()
	var dir = DirAccess.open(base_dir)
	if dir.dir_exists(TEMP_DIR):
		dir.change_dir(TEMP_DIR)
		var files = dir.get_files()
		for file_name in files:
			dir.remove(file_name)
		dir.change_dir("..")
		dir.remove(TEMP_DIR)
		print("Cleaned up temporary files")

func _process(_delta):
	pass 

func update_download_info():
	if workflow_runs.size() == 0:
		return
	
	var current_run = workflow_runs[current_workflow_index]
	
	left_text.text = truncate_text(REPO, 9)
	if is_typing_repo:
		middle_text.text = "Enter repo: " + typed_repo
	else:
		middle_text.text = "%s/%s (%s)" % [OWNER, REPO, current_run.head_sha.substr(0, 7)]
	
	if not is_downloading:
		right_text.text = "Ready | 0s"

func _handle_download_error(error_message: String):
	download_retries += 1
	
	if download_retries < MAX_RETRIES:
		print("Download attempt %d failed: %s" % [download_retries, error_message])
		right_text.text = "Retrying... (%d/%d)" % [download_retries, MAX_RETRIES]
		await get_tree().create_timer(1.0).timeout
		_attempt_download()
	else:
		print("Download failed after %d attempts: %s" % [MAX_RETRIES, error_message])
		right_text.text = error_message
		is_downloading = false

func _attempt_download():
	var current_run = workflow_runs[current_workflow_index]
	
	var artifacts_url = ARTIFACTS_API_URL % [OWNER, REPO, current_run.id]
	print("Fetching artifacts from: ", artifacts_url)
	
	var headers = []
	if GITHUB_TOKEN != "":
		headers = ["Authorization: Bearer " + GITHUB_TOKEN]
	
	right_text.text = "Fetching artifacts..."
	var error = artifact_request.request(artifacts_url, headers)
	if error != OK:
		print("Failed to fetch artifacts: ", error_string(error))
		_handle_download_error("Failed to fetch artifacts!")
		return
