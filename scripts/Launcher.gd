extends Node

const GITHUB_API_URL = "https://api.github.com"
const OWNER = "FNF-CNE-Devs"
const REPO = "CodenameEngine"
const MAX_WORKFLOWS = 100
const GITHUB_TOKEN = ""

@onready var commit_name = $"../Git Text Group/git-commit-name"
@onready var workflow_name = $"../Git Text Group/git-workflow-name"
@onready var trigger_commit = $"../Git Text Group/git-trigger-name"
@onready var author_name = $"../Git Text Group/git-author-name2"
@onready var commit_hash = $"../Git Text Group/git-author-name3"
@onready var page_counter = $"../Git Text Group/page-counter"

var http_request: HTTPRequest
var current_workflow_index = 0
var workflow_runs = []

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
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
	
	update_page_counter()

func update_page_counter():
	var total = workflow_runs.size()
	var current = current_workflow_index + 1 if total > 0 else 0
	page_counter.text = "%d/%d" % [current, total]

func _input(event):
	if event.is_action_pressed("ui_left"):
		change_workflow(-1)
	elif event.is_action_pressed("ui_right"):
		change_workflow(1)

func change_workflow(direction):
	if workflow_runs.size() == 0:
		return
	
	current_workflow_index = (current_workflow_index + direction) % workflow_runs.size()
	if current_workflow_index < 0:
		current_workflow_index = workflow_runs.size() - 1
	
	update_workflow_display()

func _process(_delta):
	pass 
