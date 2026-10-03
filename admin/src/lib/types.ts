export type AndroidRelease = {
  versionCode: number;
  versionName: string;
  downloadUrl: string;
  releaseNotes: string;
};
export type ReleaseState = {
  revision: number;
  enabled: boolean;
  release: AndroidRelease | null;
  updatedAt: string;
};
export const healthFields = [
  {
    key: "stoolStatus",
    label: "大便情况",
    description: "记录大便时可选择的情况。",
  },
  {
    key: "urineStatus",
    label: "小便情况",
    description: "记录小便时可选择的情况。",
  },
  {
    key: "urineColor",
    label: "小便颜色",
    description: "帮助使用者描述小便颜色。",
  },
  {
    key: "urineAppearance",
    label: "小便性状",
    description: "帮助使用者描述清澈度与泡沫。",
  },
] as const;
export type HealthKey = (typeof healthFields)[number]["key"];
export type HealthState = {
  revision: string;
  options: Record<HealthKey, string[]>;
};
export type ActionResult<T = never> = {
  error?: string;
  data?: T;
  success?: string;
};
