// ============================================================================
// SUPABASE EDGE FUNCTION - AI STUDY PLAN GENERATOR
// Location: supabase/functions/generate-study-plan/index.ts
// Production-Ready: OpenAI/Anthropic Integration, Error Handling, Validation
// ============================================================================

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.33.2";

// ============================================================================
// TYPES
// ============================================================================

interface GenerateStudyPlanRequest {
  target_exam: "lisans" | "onlisans" | "ortaogretim";
  target_score: number;
  weekly_hours: number;
  weak_subjects: string[];
}

interface StudyPlanDay {
  day_number: number;
  day_name: string;
  tasks: StudyPlanTask[];
  is_completed: boolean;
}

interface StudyPlanTask {
  id: string;
  subject_name: string;
  task_description: string;
  estimated_minutes: number;
  is_completed: boolean;
  completed_at: string | null;
}

interface StudyPlanWeek {
  week_number: number;
  days: StudyPlanDay[];
  start_date: string;
  end_date: string;
}

interface StudyPlan {
  weeks: StudyPlanWeek[];
}

// ============================================================================
// CONFIGURATION
// ============================================================================

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

const LLM_PROVIDER = Deno.env.get("LLM_PROVIDER") || "openai"; // openai | anthropic

// ============================================================================
// MAIN HANDLER
// ============================================================================

serve(async (req: Request) => {
  try {
    // =====================================================================
    // CORS & REQUEST VALIDATION
    // =====================================================================

    // Handle CORS preflight
    if (req.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      });
    }

    // Only POST allowed
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json" },
      });
    }

    // =====================================================================
    // AUTHENTICATION
    // =====================================================================

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Unauthorized - missing bearer token" }),
        {
          status: 401,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    const token = authHeader.substring(7);

    // Verify token with Supabase
    const supabase = createClient(SUPABASE_URL!, SUPABASE_SERVICE_KEY!);

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized - invalid token" }),
        {
          status: 401,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    const userId = user.id;

    // =====================================================================
    // REQUEST PARSING & VALIDATION
    // =====================================================================

    let requestBody: GenerateStudyPlanRequest;

    try {
      requestBody = await req.json();
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid JSON in request body" }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    // Validate required fields
    const validationError = validateRequest(requestBody);
    if (validationError) {
      return new Response(JSON.stringify({ error: validationError }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // =====================================================================
    // RATE LIMITING CHECK
    // =====================================================================

    const rateLimitError = await checkRateLimit(supabase, userId);
    if (rateLimitError) {
      return new Response(JSON.stringify({ error: rateLimitError }), {
        status: 429,
        headers: { "Content-Type": "application/json" },
      });
    }

    // =====================================================================
    // GENERATE STUDY PLAN WITH LLM
    // =====================================================================

    let studyPlan: StudyPlan;

    try {
      if (LLM_PROVIDER === "anthropic") {
        studyPlan = await generateWithAnthropic(requestBody);
      } else {
        studyPlan = await generateWithOpenAI(requestBody);
      }
    } catch (error) {
      console.error("LLM Error:", error);
      return new Response(
        JSON.stringify({
          error: "Failed to generate study plan",
          details: error.message,
        }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    // =====================================================================
    // VALIDATE & SAVE STUDY PLAN
    // =====================================================================

    // Validate generated plan structure
    if (!isValidStudyPlan(studyPlan)) {
      return new Response(
        JSON.stringify({ error: "Invalid study plan structure from LLM" }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    // Save to Supabase
    const saveError = await saveStudyPlanToSupabase(supabase, userId, studyPlan);
    if (saveError) {
      return new Response(JSON.stringify({ error: saveError }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    // =====================================================================
    // RECORD USAGE
    // =====================================================================

    await recordUsage(supabase, userId);

    // =====================================================================
    // RETURN RESPONSE
    // =====================================================================

    return new Response(JSON.stringify({ success: true, data: studyPlan }), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (error) {
    console.error("Unhandled Error:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: error.message,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
});

// ============================================================================
// VALIDATION FUNCTIONS
// ============================================================================

function validateRequest(req: GenerateStudyPlanRequest): string | null {
  if (!req.target_exam) {
    return "target_exam is required";
  }

  if (!["lisans", "onlisans", "ortaogretim"].includes(req.target_exam)) {
    return "target_exam must be one of: lisans, onlisans, ortaogretim";
  }

  if (typeof req.target_score !== "number" || req.target_score < 0 || req.target_score > 100) {
    return "target_score must be a number between 0 and 100";
  }

  if (typeof req.weekly_hours !== "number" || req.weekly_hours < 5 || req.weekly_hours > 70) {
    return "weekly_hours must be a number between 5 and 70";
  }

  if (!Array.isArray(req.weak_subjects) || req.weak_subjects.length === 0) {
    return "weak_subjects must be a non-empty array";
  }

  return null;
}

async function checkRateLimit(supabase: any, userId: string): Promise<string | null> {
  try {
    const today = new Date().toISOString().split("T")[0];

    const { data, error } = await supabase
      .from("study_plan_requests")
      .select("count")
      .eq("user_id", userId)
      .eq("date", today)
      .single();

    if (error && error.code !== "PGRST116") {
      console.error("Rate limit check error:", error);
      return null; // Allow on error
    }

    const count = data?.count || 0;
    const limit = 3; // Max 3 requests per day

    if (count >= limit) {
      const resetTime = new Date();
      resetTime.setDate(resetTime.getDate() + 1);
      resetTime.setHours(0, 0, 0, 0);

      return `Rate limit exceeded. You can generate ${limit} study plans per day. Try again at ${resetTime.toISOString()}`;
    }

    return null;
  } catch (error) {
    console.error("Rate limit check failed:", error);
    return null; // Allow on error
  }
}

function isValidStudyPlan(plan: StudyPlan): boolean {
  if (!plan || !Array.isArray(plan.weeks)) {
    return false;
  }

  for (const week of plan.weeks) {
    if (
      !week.week_number ||
      !Array.isArray(week.days) ||
      !week.start_date ||
      !week.end_date
    ) {
      return false;
    }

    for (const day of week.days) {
      if (!day.day_number || !day.day_name || !Array.isArray(day.tasks)) {
        return false;
      }

      for (const task of day.tasks) {
        if (!task.id || !task.subject_name || !task.task_description || !task.estimated_minutes) {
          return false;
        }
      }
    }
  }

  return true;
}

// ============================================================================
// LLM PROVIDERS - OpenAI
// ============================================================================

async function generateWithOpenAI(request: GenerateStudyPlanRequest): Promise<StudyPlan> {
  if (!OPENAI_API_KEY) {
    throw new Error("OpenAI API key not configured");
  }

  const systemPrompt = buildSystemPrompt(request);
  const userPrompt = buildUserPrompt(request);

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: "gpt-4-turbo-preview",
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      temperature: 0.7,
      max_tokens: 4000,
      response_format: { type: "json_object" },
    }),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(`OpenAI API error: ${error.error?.message}`);
  }

  const data = await response.json();
  const content = data.choices[0]?.message?.content;

  if (!content) {
    throw new Error("No content in OpenAI response");
  }

  return JSON.parse(content);
}

// ============================================================================
// LLM PROVIDERS - Anthropic
// ============================================================================

async function generateWithAnthropic(
  request: GenerateStudyPlanRequest
): Promise<StudyPlan> {
  if (!ANTHROPIC_API_KEY) {
    throw new Error("Anthropic API key not configured");
  }

  const systemPrompt = buildSystemPrompt(request);
  const userPrompt = buildUserPrompt(request);

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-3-opus-20240229",
      max_tokens: 4000,
      messages: [
        {
          role: "user",
          content: `${systemPrompt}\n\n${userPrompt}\n\nRespond ONLY with valid JSON, no markdown or extra text.`,
        },
      ],
    }),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(`Anthropic API error: ${error.error?.message}`);
  }

  const data = await response.json();
  const content = data.content[0]?.text;

  if (!content) {
    throw new Error("No content in Anthropic response");
  }

  return JSON.parse(content);
}

// ============================================================================
// PROMPT BUILDERS
// ============================================================================

function buildSystemPrompt(request: GenerateStudyPlanRequest): string {
  return `You are an expert KPSS (Turkish Public Personnel Selection Exam) study coach.
Your task is to create a detailed, personalized 12-week study plan in Turkish.

The study plan MUST be valid JSON with this exact structure:
{
  "weeks": [
    {
      "week_number": 1,
      "days": [
        {
          "day_number": 1,
          "day_name": "Pazartesi",
          "tasks": [
            {
              "id": "unique-task-id",
              "subject_name": "Tarih",
              "task_description": "Osmanlı dönemi - siyasi yapı",
              "estimated_minutes": 45,
              "is_completed": false,
              "completed_at": null
            }
          ],
          "is_completed": false
        }
      ],
      "start_date": "2024-02-12T00:00:00Z",
      "end_date": "2024-02-18T23:59:59Z"
    }
  ]
}

Requirements:
- Generate 12 weeks of study plan
- Each week has 7 days (Pazartesi to Pazar)
- Focus on weak subjects: ${request.weak_subjects.join(", ")}
- Total weekly hours: ${request.weekly_hours}
- Target exam: ${request.target_exam}
- Target score: ${request.target_score}
- Each day should have 2-4 tasks
- Tasks should be specific and measurable
- Vary subjects throughout the week
- Include rest/review days
- Gradually increase difficulty
- End-of-week review sessions
- Response MUST be ONLY valid JSON, no markdown or extra text`;
}

function buildUserPrompt(request: GenerateStudyPlanRequest): string {
  return `Create a 12-week KPSS ${request.target_exam} study plan with these parameters:
- Target Score: ${request.target_score}/100
- Weekly Study Hours: ${request.weekly_hours}
- Weak Subjects: ${request.weak_subjects.join(", ")}
- Today's Date: ${new Date().toISOString()}

The plan should:
1. Prioritize weak subjects (2x more focus than strong ones)
2. Balance all KPSS subject categories (Sözel, Sayısal, Tamamlayıcı)
3. Include daily review of previous topics
4. Have realistic time allocations based on weekly_hours
5. Include practice tests every Friday
6. Have comprehensive review week before exam
7. Adapt difficulty based on progress expectations
8. Include motivational milestones

Return ONLY valid JSON, nothing else.`;
}

// ============================================================================
// SUPABASE OPERATIONS
// ============================================================================

async function saveStudyPlanToSupabase(
  supabase: any,
  userId: string,
  plan: StudyPlan
): Promise<string | null> {
  try {
    // Deactivate previous plans
    await supabase
      .from("ai_study_plans")
      .update({ is_active: false })
      .eq("user_id", userId)
      .eq("is_active", true);

    // Insert new plan
    const { error } = await supabase.from("ai_study_plans").insert({
      user_id: userId,
      plan_data: plan,
      is_active: true,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });

    if (error) {
      return `Failed to save study plan: ${error.message}`;
    }

    return null;
  } catch (error) {
    return `Database error: ${error.message}`;
  }
}

async function recordUsage(supabase: any, userId: string): Promise<void> {
  try {
    const today = new Date().toISOString().split("T")[0];

    await supabase.from("study_plan_requests").upsert(
      {
        user_id: userId,
        date: today,
        count: 1,
      },
      { onConflict: "user_id,date" }
    );
  } catch (error) {
    console.error("Failed to record usage:", error);
    // Don't throw, just log
  }
}

// ============================================================================
// END OF EDGE FUNCTION
// ============================================================================
