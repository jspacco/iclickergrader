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
  def initialize(csv_own = nil, csv_borrow = nil)
    # hash from session_code to number of questions
    # list of all clicker IDs for the whole term
    # hash from session_code to hash from clicker_id to number of votes
    @num_questions = Hash.new(0)
    @clicker_ids = Set.new
    @votes = Hash.new
    @emails = Set.new

    # clicker_id => email
    # convert to:
    # email => set of clicker_id
    # also add all emails to @emails
    @own = Hash.new
    csv_own.each do |clicker_id, email|
      @emails.add(email)
      if !@own.key?(email)
        @own[email] = Set.new
      end
      @own[email].add(clicker_id)
    end
    # date => email => clicker_id
    @borrow = csv_borrow
    # add all the emails to our list of emails, if they aren't already there
    @borrow.each do |date, hash|
      for email in hash.keys
        @emails.add(email)
      end
    end
  end

  def to_csv
    out = "email,"
    for session_code in @num_questions.keys.sort
      out += "#{get_datetime(session_code)},"
    end
    for email in @emails
      # borrow is:
      # date => clicker_id => email
      # own is:
      # email => set of clicker_ids
      out += "#{email},"
      # go through each class period
      for session_code in @num_questions.keys.sort
        # get clicker_ids for this email, for this day
        clickers = Set.new
        # if !@own.key?(email)
        #   STDERR.puts "NO CLICKER FOR #{email}"
        #   next
        # end
        @own[email].each do |clicker_id|
          clickers.add(clicker_id)
        end
        # if on this date, this email borrowed a clicker, add it to the set
        # of clickers used by this student
        if @borrow.key?(session_code) && @borrow[session_code].key?(email)
          clickers.add(@borrow[session_code][email])
        end
        # clickers now contains all clicker_ids used by a student
        # over the term, or on the given day
        found = false
        for clicker_id in clickers
          puts @votes[session_code][clicker_id]
          if @votes[session_code][clicker_id] > 0
            found = true
          end
        end
        if found
          out += "1,"
        else
          out += "0,"
        end
      end
      out += "\n"
    end
    return out
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

  def get_vote(session_code, clicker_id)
    # if we have a CSV lookup, use it
    if @csv != nil
      if @csv.key?(clicker_id)
        return @votes[session_code][clicker_id].to_s + '<br>' +
          @csv[clicker_id]
      else
        return @votes[session_code][clicker_id].to_s
      end
    else
      return @votes[session_code][clicker_id].to_s
    end
  end

  def get_name_or_clicker(clicker_id)
    if @own.key? clicker_id
      return @own[clicker_id]
    else
      return clicker_id
    end
  end

  def html
    # TODO: add a way to de-anonymize, by putting in the person's name instead
    # of just the thing
    title = "title"
    out = "<html><head><title>#{title}</title>\n"
    out += "<style>\n"
    out += "td.green {background-color: green;}\n"
    out += "td.red {background-color: red;}\n"
    out += "</style>\n"
    out += "</head>\n"
    out += "<body>\n"
    out += "<table border=1>\n<tr><th>clicker ID</th>\n"
    for session_code in @num_questions.keys.sort
      out += "  <th>#{get_datetime(session_code)}<br><br>#{@num_questions[session_code]} questions</th>\n"
    end
    out += "</tr>\n"
    for clicker_id in @clicker_ids.sort
      out += "<tr>\n"
      out += "  <td>#{get_name_or_clicker(clicker_id)}</td>\n"
      for session_code in @num_questions.keys.sort
        if @votes[session_code][clicker_id] > (3*@num_questions[session_code]/4)
          out += "  <td class=\"green\">#{get_vote(session_code, clicker_id)}</td>\n"
        elsif @votes[session_code][clicker_id] == 0
          out += "  <td class=\"red\">#{get_vote(session_code, clicker_id)}</td>\n"
        else
          out += "  <td>#{get_vote(session_code, clicker_id)}</td>\n"
        end
      end
      out += "</tr>\n"
    end
    out += "</table></body></html>\n"
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
        end
      end
    end
  end

  def process_course(folder)
    session_path = "#{folder}/SessionData/*.xml"
    Dir.glob(session_path) do |session_file|
      next if File.basename(session_file).start_with?("x")
      parse_XML(session_file)
    end
  end
end


if __FILE__ == $0
  opts = GetoptLong.new(
    [ '--outfile', '-o', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--csvregularfile', '-r', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--csvborrowfile', '-b', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--csv', '-c', GetoptLong::NO_ARGUMENT ]
  )

  outfile = nil
  csvregular = nil
  csvborrow = nil
  output = :html
  opts.each do |opt, arg|
    case opt
      when '--outfile'
        outfile = arg
      when '--csv'
        output = :csv
      when '--csvregularfile'
        csvregular = Hash.new
        # skip the header row
        CSV.read(arg)[1 .. -1].each do |row|
        #CSV.foreach(arg) do |row|
          email = row[1].gsub('@knox.edu', '')
          clicker = row[2]
          csvregular[clicker] = email
        end
      when '--csvborrowfile'
        csvborrow = Hash.new
        # skip the header row
        CSV.read(arg)[1 .. -1].each do |row|
        #CSV.foreach(arg) do |row|
          email = row[1].gsub('@knox.edu', '')
          clicker = row[2]
          datestr = row[3]
          month, day, year = row[3].split('-')
          begin
            date = Date.new(month.to_i, day.to_i, year.to_i)
          rescue ArgumentError
            STDERR.puts "ROWBAR #{row}"
            STDERR.puts "FOOBAR #{month}, #{day}, #{year}"
            raise
          end
          if !csvborrow.key? datestr
            csvborrow[datestr] = Hash.new
          end
          csvborrow[datestr][email] = clicker
        end
    end
  end

  if ARGV.length < 1
    puts "Usage: #{$0} [ -r <csvregularfile> ] [ -b <csvborrowfile> ] [ -o <outfile> ] [ -c / --csv ] <course_folder>"
    exit
  end
  classdir = ARGV.shift

  course = Course.new(csvregular, csvborrow)
  course.process_course(classdir)

  result = nil
  if output == :html
    result = course.html
  elsif output == :csv
    result = course.to_csv
  end

  # TODO: Output can be CSV, anonymous CSV, HTML, anonymous HTML
  if outfile == nil
    puts result
  else
    File.open(outfile, 'w') { |file| file.write(result) }
  end
end
