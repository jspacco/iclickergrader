require 'nokogiri'
require 'set'

def get_datetime(filename)
  # L1609120921.xml
  # L == class_period
  # 16 == 2016
  # 0912 == September 12
  # 0921 == 9:21am
  file = filename
  if filename.end_with?('.xml')
    file = File.basename(filename, '.xml')
  end
  m = file.match(/L(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/)
  year, month, day, hour, minute = m.captures
  #return DateTime.new(2000 + year.to_i, month.to_i, day.to_i, hour.to_i, minute.to_i)
  return "20#{year}-#{month}-#{day}"
end

# process clicker data for the whole term and compute attendance
class Course
  def initialize
    # hash from session_code to number of questions
    # list of session_code in correct order
    # list of all clicker IDs for the whole term
    # hash from session_code to hash from clicker_id to number of votes
    @num_questions = Hash.new(0)
    @clicker_ids = Set.new
    @votes = Hash.new
  end

  def add_question(session_code)
    @num_questions[session_code] += 1
  end

  def add_clicker_vote(session_code, clicker_id)
    @clicker_ids.add(clicker_id)
    if !@votes.key?(session_code)
      @votes[session_code] = Hash.new(0)
    end
    if !@votes[session_code].key?(clicker_id)
      @votes[session_code][clicker_id] = 0
    end
    @votes[session_code][clicker_id] += 1
    # puts "just added #{session_code} with #{clicker_id}"
  end

  def html
    title = "title"
    out = "<html><head><title>#{title}</title></head>\n"
    out += "<table border=1>\n<tr><th>clicker ID</th>\n"
    for session_code in @num_questions.keys.sort
      out += "  <th>#{get_datetime(session_code)}<br><br>#{@num_questions[session_code]} questions</th>\n"
    end
    out += "</tr>\n"
    for clicker_id in @clicker_ids.sort
      out += "<tr>\n"
      out += "  <td>#{clicker_id}</td>\n"
      for session_code in @num_questions.keys.sort
        out += "  <td>#{@votes[session_code][clicker_id]}</td>\n"
      end
      out += "</tr>\n"
    end
    return out
  end

  def parse_XML(filename)
    page = Nokogiri::XML(open(filename))

    session_code = File.basename(filename, '.xml')

    # Each file should only have one session (class_period) in it
    page.css('//ssn').each do |ssn|
      name = ssn['ssnn']

      # go through each clicker question (or problem, which is why the key is p)
      ssn.css('p').each do |prob|
        add_question(session_code)
        question_name = prob['qn']

        # go through each vote
        prob.css('v').each do |vote|
          clicker_id = vote['id']
          if vote['ans'] != ''
            add_clicker_vote(session_code, clicker_id)
          end
          # puts "#{clicker_id}"
        end
      end
    end
  end

  def process_course(folder, outfile=nil)
    course = Course.new
    session_path = "#{folder}/SessionData/*.xml"
    Dir.glob(session_path) do |session_file|
      next if File.basename(session_file).start_with?("x")
      course.parse_XML(session_file, course)
    end
    # TODO if stdout then don't write to file
    if outfile == nil
      puts html
    else
      File.open(outfile, 'w') { |file| file.write(course.html) }
    end
  end
end


if __FILE__ == $0
  classdir = 'class1'
  classdir = '/Users/jspacco/projects/clickers/data/UIC.CS111F17'
  classdir = '/Users/jspacco/projects/clickers/data/UCSD.CSE141F15'
  course = Course.new
  outfile = 'out.html'
  course.process_course(classdir, 'out.html')
end
