class SampleReviewsController < ApplicationController
	skip_before_action :authorize, only: [:update_visibility, :show, :index]

	def show
		response_id = params[:id]
		q_and_a_data = Answer.joins("INNER JOIN questions ON question_id = questions.id WHERE answers.response_id=#{response_id.to_s}")
		
		questions_query_result = Question.find(q_and_a_data.pluck(:question_id))
		questions_map = {}
		questions_query_result.each do |question|
			if !questions_map.key?(question.id)
				questions_map[question.id] = question.txt
			end
		end
		@qa_table = []
		q_and_a_data.each do |answer|
			question_text = questions_map[answer.question_id]
			answer_text = answer.comments.strip
			if question_text.size > 0 and answer_text.size > 0
				@qa_table.push({:question=>question_text,:answer=>answer_text})
			end
		end
		assignment_id = ResponseMap.find(Response.find(response_id).map_id).reviewed_object_id
		@course_assignment_name = get_course_assignment_name(assignment_id)
	end

	def index
		assignment_participant_id = params[:id]
		assignment_id = AssignmentParticipant.find(assignment_participant_id).parent_id
		similar_assignment_ids = SimilarAssignment.where(:assignment_id => assignment_id).pluck(:is_similar_for)
		@response_ids = []
		similar_assignment_ids.each do |id|
			ids = Response.joins("INNER JOIN response_maps ON response_maps.id = responses.map_id WHERE visibility=2 AND reviewed_object_id = "+id.to_s ).ids
			@response_ids += ids
		end
		@links = generate_links(@response_ids)

		@course_assignment_name = get_course_assignment_name(assignment_id)
	end

	def update_visibility
		begin
			@@response_id = params[:id]
			response_map_id = Response.find(@@response_id).map_id
			assignment_id = ResponseMap.find(response_map_id).reviewed_object_id
			course_id = Assignment.find(assignment_id).course_id
			instructor_id = Course.find(course_id).instructor_id
			ta_ids = []
			if current_user.role.name == 'Teaching Assistant'
				ta_ids = TaMapping.where(course_id).ids # do this query only if current user is ta
			end
			if not ([instructor_id] + ta_ids).include? current_user.id
			 	render json:{"success" => false,"error" => "Unathorized"}
			 	return
			end
			visibility = params[:visibility].to_i #response object consists of visibility in string format
			if not (0..3).include? visibility
				raise StandardError.new('Invalid visibility')
			end
			Response.update(@@response_id.to_i, :visibility => visibility)
			update_similar_assignment(assignment_id, visibility)
		rescue StandardError
			render json:{"success" => false,"error" => "Something went wrong"}
		else
			render json:{"success" => true}
		end
	end

	private
	def update_similar_assignment(assignment_id, visibility)
		if visibility == 2 
			ids = SimilarAssignment.where(:is_similar_for => assignment_id, :association_intent => 'Review', 
				:assignment_id => assignment_id).ids
			if ids.empty?
				SimilarAssignment.create({:is_similar_for => assignment_id, :association_intent => 'Review', 
				:assignment_id => assignment_id})
			end
		end
		if visibility == 3 or visibility == 0
			response_map_ids = ResponseMap.where(:reviewed_object_id => assignment_id).ids
			response_ids = Response.where(:map_id => response_map_ids, :visibility => 2)
			if response_ids.empty?
				SimilarAssignment.where(:assignment_id => assignment_id).destroy_all
			end
		end
	end

	def generate_links(response_ids)
		links = []
		response_ids.each do |id|
			links.append('/sample_reviews/show/' + id.to_s)
		end
		links
	end

	def get_course_assignment_name(assignment_id)
		assignment_name = Assignment.find(assignment_id).name
		course_id = Assignment.find(assignment_id).course_id
		course_name = Course.find(course_id).name
		if course_name.size > 0 && assignment_name.size > 0
			course_assignment_name = course_name + " - " + assignment_name
		elsif course_name.size > 0
			course_assignment_name = course_name
		elsif assignment_name.size > 0
			course_assignment_name = assignment_name
		else
			course_assignment_name = "assignment"
		end
		return course_assignment_name
	end
end