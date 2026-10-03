import { Skeleton } from "@/components/ui/skeleton";
export default function Loading() {
  return (
    <div role="status" aria-label="正在加载" className="flex flex-col gap-6">
      <Skeleton className="h-9 w-48" />
      <Skeleton className="h-5 w-72 max-w-full" />
      <Skeleton className="mt-5 h-64 w-full" />
    </div>
  );
}
