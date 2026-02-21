import { NextRequest, NextResponse } from "next/server";
import { getServiceSupabase } from "@/lib/supabase";

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const supabase = getServiceSupabase();

    const { data, error } = await supabase
      .from("reports")
      .select("*")
      .eq("id", id)
      .single();

    if (error || !data) {
      return NextResponse.json({ error: "Report not found" }, { status: 404 });
    }

    // Also fetch history for this machine (last 10 reports)
    const { data: history } = await supabase
      .from("reports")
      .select("id, score, created_at")
      .eq("machine_id", data.machine_id)
      .order("created_at", { ascending: false })
      .limit(10);

    return NextResponse.json({
      ...data,
      history: history || [],
    });
  } catch (e) {
    console.error("Report fetch error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
