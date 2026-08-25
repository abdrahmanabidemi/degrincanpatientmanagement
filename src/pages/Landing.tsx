import { useEffect, useState } from "react";
import { Navigate } from "react-router-dom";
import { useAuth } from "@/lib/auth";
import { BrandLoader } from "@/components/BrandLoader";

// The app opens directly into either the dashboard (if signed in) or the auth screen.
export default function Landing() {
  const { user, loading } = useAuth();
  const [timedOut, setTimedOut] = useState(false);

  useEffect(() => {
    const timer = setTimeout(() => setTimedOut(true), 1500);
    return () => clearTimeout(timer);
  }, []);

  if (loading && !timedOut) return <BrandLoader label="Loading..." />;
  return <Navigate to={user ? "/dashboard" : "/auth"} replace />;
}
