-- Deep Talk, Business and Speak Better cards (kept in the database so only members can read them). Safe to run more than once.
insert into public.sections (track, position, title, tags, detail_label, details, route) values
('deep_talk', 1, 'Relationships', array['24 questions', 'Medium', 'Depth 4/5']::text[], 'Sample questions', array['What does feeling cared for look like to you?', 'When did you last feel truly understood?']::text[], NULL),
('deep_talk', 2, 'Dreams', array['18 questions', 'Easy', 'Depth 3/5']::text[], 'Sample questions', array['What would you do if you could not fail?', 'What would be your first step?']::text[], NULL),
('deep_talk', 3, 'Values', array['20 questions', 'Medium', 'Depth 4/5']::text[], 'Sample questions', array['What principle would you never compromise on?', 'Where did you learn it?']::text[], NULL),
('deep_talk', 4, 'Success', array['16 questions', 'Medium', 'Depth 3/5']::text[], 'Sample questions', array['How do you define success for yourself?', 'Has that changed over time?']::text[], NULL),
('deep_talk', 5, 'Life Vision', array['15 questions', 'Hard', 'Depth 5/5']::text[], 'Sample questions', array['What does your ideal day look like in five years?', 'What can you do now to move toward it?']::text[], NULL),
('deep_talk', 6, 'Personal Growth', array['22 questions', 'Medium', 'Depth 4/5']::text[], 'Sample questions', array['What have you changed your mind about?', 'What caused the shift?']::text[], NULL),
('deep_talk', 7, 'Family', array['19 questions', 'Hard', 'Depth 5/5']::text[], 'Sample questions', array['Who in your family shaped you the most?', 'What did you learn from them?']::text[], NULL),
('deep_talk', 8, 'Travel', array['17 questions', 'Easy', 'Depth 2/5']::text[], 'Sample questions', array['Which trip changed how you see things?', 'What stayed with you afterwards?']::text[], NULL),
('business', 1, 'Networking', array['AI suggestion']::text[], 'Coach', array['Ask about their current challenge, then offer one useful introduction.']::text[], NULL),
('business', 2, 'Sales', array['AI suggestion']::text[], 'Coach', array['Diagnose first: "What would make this a clear success for you?"']::text[], NULL),
('business', 3, 'Negotiations', array['AI suggestion']::text[], 'Coach', array['Trade, do not concede: "If we extend the term, can we adjust the price?"']::text[], NULL),
('business', 4, 'Leadership', array['AI suggestion']::text[], 'Coach', array['State what, why and how you will support. Keep it specific and kind.']::text[], NULL),
('business', 5, 'Presentations', array['AI suggestion']::text[], 'Coach', array['Open with the result, give three points, close with one clear action.']::text[], NULL),
('business', 6, 'Meetings', array['AI suggestion']::text[], 'Coach', array['Start with the conclusion, confirm owners and next steps in writing.']::text[], NULL),
('business', 7, 'Client Communication', array['AI suggestion']::text[], 'Coach', array['Mirror their priorities and summarize decisions after each call.']::text[], NULL),
('speak', 1, 'Voice Analysis', array['Studio']::text[], 'How it works', array['Record up to 60 seconds. You get scores for pace, pitch, pauses, confidence and more, with tips.']::text[], '/studio/voice'),
('speak', 2, 'Articulation Training', array['Daily']::text[], 'Drill', array['Say "Red lorry, yellow lorry" ten times, slowly then fast.']::text[], NULL),
('speak', 3, 'Storytelling', array['Weekly']::text[], 'Drill', array['Tell a 60-second story: hook, problem, turning point, lesson.']::text[], NULL),
('speak', 4, 'Charisma Lab', array['Levels 1 to 4']::text[], 'Exercise', array['Pause two seconds before answering one hard question today.']::text[], NULL),
('speak', 5, 'Daily Speaking Challenge', array['Daily']::text[], 'Challenge', array['Explain your job in 30 seconds to an imaginary friend.']::text[], NULL)
on conflict (track, title) do nothing;
