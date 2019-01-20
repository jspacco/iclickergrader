require 'nokogiri'
require 'set'
require 'getoptlong'
require 'csv'

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
  def initialize(csv = nil)
    # hash from session_code to number of questions
    # list of all clicker IDs for the whole term
    # hash from session_code to hash from clicker_id to number of votes
    @num_questions = Hash.new(0)
    @clicker_ids = Set.new
    @votes = Hash.new
    @csv = csv
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
  end

  def get(session_code, clicker_id)
    # if we have a CSV lookup, use it
    if @csv != nil
      if @csv.key?(clicker_id)
        return @votes[session_code][clicker_id].to_s + '<br>' +
          @csv[clicker_id]
      else
        return @votes[session_code][clicker_id].to_s + '<br>?'
      end
    else
      return @votes[session_code][clicker_id].to_s
    end
  end

  def html(csv = nil)
    title = "title"
    out = "<html><head><title>#{title}</title>\n"
    out += "<style>\n"
    out += "td.green {background-color: green;}\n"
    out += "td.red {background-color: red;}\n"
    out += "</style>\n"
    out += "</head>\n"
    out += "<table border=1>\n<tr><th>clicker ID</th>\n"
    for session_code in @num_questions.keys.sort
      out += "  <th>#{get_datetime(session_code)}<br><br>#{@num_questions[session_code]} questions</th>\n"
    end
    out += "</tr>\n"
    for clicker_id in @clicker_ids.sort
      out += "<tr>\n"
      out += "  <td>#{clicker_id}</td>\n"
      for session_code in @num_questions.keys.sort
        if @votes[session_code][clicker_id] > (3*@num_questions[session_code]/4)
          out += "  <td class=\"green\">#{get(session_code, clicker_id)}</td>\n"
        elsif @votes[session_code][clicker_id] == 0
          out += "  <td class=\"red\">#{get(session_code, clicker_id)}</td>\n"
        else
          out += "  <td>#{get(session_code, clicker_id)}</td>\n"
        end
      end
      out += "</tr>\n"
    end
    return out
  end

  def parse_XML(filename, csv)
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
        end
      end
    end
  end

  def process_course(folder, csv=nil)
    course = Course.new
    session_path = "#{folder}/SessionData/*.xml"
    Dir.glob(session_path) do |session_file|
      next if File.basename(session_file).start_with?("x")
      parse_XML(session_file, csv)
    end
  end
end


if __FILE__ == $0
  opts = GetoptLong.new(
    [ '--outfile', '-o', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--csvfile', '-c', GetoptLong::REQUIRED_ARGUMENT ]
  )

  outfile = nil
  csv = Hash.new
  csvfile = nil
  opts.each do |opt, arg|
    case opt
      when '--outfile'
        outfile = arg
      when '--csvfile'
        csvfile = arg
    end
  end

  if ARGV.length < 1
    puts "Usage: #{$0} [ -c <csvfile> ] [ -o <outfile> ] <course_folder>"
    exit
  end
  classdir = ARGV.shift

  if csvfile != nil
    #CSV.foreach(csv, headers:true) do |row|
    CSV.foreach(csvfile) do |row|
      email = row[1].gsub('@knox.edu', '')
      clicker = row[2]
      csv[clicker] = email
    end
  end

  course = Course.new(csv)
  course.process_course(classdir, csv)

  if outfile == nil
    puts course.html
  else
    File.open(outfile, 'w') { |file| file.write(course.html) }
  end
end
