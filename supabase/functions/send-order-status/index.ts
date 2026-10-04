import { createClient } from "jsr:@supabase/supabase-js@2";

type WebhookPayload = {
  record?: Record<string, unknown>;
  old_record?: Record<string, unknown>;
};

type FirebaseAccessToken = {
  access_token: string;
  expires_in: number;
  token_type: string;
};

type PushPayload = {
  title: string;
  body: string;
  data: Record<string, string>;
  channelId: string;
  includeNotification?: boolean;
};

const textEncoder = new TextEncoder();

function getEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

function base64UrlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? textEncoder.encode(input) : input;
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const normalized = pem.replace(/\\n/g, "\n");
  const base64 = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");

  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function formatStatusPhrase(orderStatus: string): string {
  const normalized = orderStatus.trim().toLowerCase();

  switch (normalized) {
    case "pending":
      return "received";
    case "confirmed":
      return "confirmed";
    case "accepted":
      return "accepted";
    case "preparing":
      return "being prepared";
    case "ready":
    case "ready_for_pickup":
      return "ready";
    case "on_the_way":
    case "out_for_delivery":
      return "on the way";
    case "picked_up":
      return "picked up";
    case "delivered":
      return "delivered";
    case "cancelled":
    case "canceled":
      return "cancelled";
    default:
      return normalized.replace(/_/g, " ");
  }
}

function buildStatusNotificationBody(
  orderStatus: string,
  orderNumber: string,
  hasMultipleOrders: boolean,
): string {
  const normalized = orderStatus.trim().toLowerCase();
  const orderLabel = hasMultipleOrders && orderNumber
    ? `Order #${orderNumber}`
    : "Your order";

  switch (normalized) {
    case "accepted":
      return `${orderLabel} has been accepted. Please pay for it to confirm your order.`;
    case "cancelled":
    case "canceled":
      return `Sorry, ${orderLabel.toLowerCase()} has been cancelled.`;
    default: {
      const prettyStatus = formatStatusPhrase(orderStatus);
      return hasMultipleOrders
        ? `${orderLabel} is now ${prettyStatus}.`
        : `Your order has been ${prettyStatus}.`;
    }
  }
}

function isTruthy(value: unknown): boolean {
  if (typeof value === "boolean") {
    return value;
  }

  const normalized = String(value ?? "")
    .trim()
    .toLowerCase();
  return normalized === "true" || normalized === "1" || normalized === "yes";
}

function inferServiceType(record: Record<string, unknown>): string {
  const deliveryFeeCents = Number(record.delivery_fee_cents ?? 0);
  if (
    deliveryFeeCents > 0 ||
    record.delivery_address != null ||
    record.delivery_lat != null ||
    record.delivery_lng != null
  ) {
    return "delivery";
  }

  const items = Array.isArray(record.items_json) ? record.items_json : [];
  const firstItem = items[0];
  if (firstItem && typeof firstItem === "object" && "order_type" in firstItem) {
    const orderType = String(
      (firstItem as Record<string, unknown>).order_type ?? "",
    ).trim();
    if (orderType) {
      return orderType;
    }
  }

  return "pickup";
}

function isTokenInvalidationError(message: string): boolean {
  const normalized = message.toLowerCase();
  return (
    normalized.includes("registration-token-not-registered") ||
    normalized.includes("invalid-registration-token") ||
    normalized.includes("unregistered")
  );
}

async function createGoogleAccessToken(): Promise<string> {
  const clientEmail = getEnv("FIREBASE_CLIENT_EMAIL");
  const privateKey = getEnv("FIREBASE_PRIVATE_KEY");

  const now = Math.floor(Date.now() / 1000);
  const header = {
    alg: "RS256",
    typ: "JWT",
  };
  const claimSet = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const unsignedJwt = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(claimSet))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    textEncoder.encode(unsignedJwt),
  );
  const signedJwt = `${unsignedJwt}.${base64UrlEncode(new Uint8Array(signature))}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: signedJwt,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Failed to get Google access token: ${body}`);
  }

  const token = (await response.json()) as FirebaseAccessToken;
  return token.access_token;
}

async function sendPushToToken(
  accessToken: string,
  projectId: string,
  pushToken: string,
  payload: PushPayload,
) {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: pushToken,
          ...(payload.includeNotification === false
            ? {}
            : {
                notification: {
                  title: payload.title,
                  body: payload.body,
                },
              }),
          data: {
            ...payload.data,
            title: payload.title,
            body: payload.body,
          },
          android: payload.includeNotification === false
            ? {
                priority: "high",
              }
            : {
                priority: "high",
                notification: {
                  channel_id: payload.channelId,
                  sound: "default",
                },
              },
        },
      }),
    },
  );

  if (!response.ok) {
    const body = await response.text();
    throw new Error(body);
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const webhookPayload = (await request.json()) as WebhookPayload;
    const record = webhookPayload.record ?? {};
    const oldRecord = webhookPayload.old_record ?? {};

    const orderId = String(record.id ?? "");
    const orderNumber = String(record.order_numbers ?? "").trim();
    const customerId = String(record.customer_id ?? "");
    const nextStatus = String(record.status ?? "");
    const previousStatus = String(oldRecord.status ?? "");
    const nextAlert = isTruthy(record.alert);
    const previousAlert = isTruthy(oldRecord.alert);
    const alertActivated = nextAlert && !previousAlert;
    const statusChanged =
      Boolean(orderId && customerId && nextStatus) && previousStatus !== nextStatus;

    if (!orderId || !customerId || (!statusChanged && !alertActivated)) {
      return Response.json({ skipped: true });
    }

    const supabase = createClient(
      getEnv("SUPABASE_URL"),
      getEnv("SUPABASE_SERVICE_ROLE_KEY"),
      { auth: { persistSession: false } },
    );

    const { count: orderCount, error: orderCountError } = await supabase
      .from("orders")
      .select("id", { count: "exact", head: true })
      .eq("customer_id", customerId);

    if (orderCountError) {
      throw orderCountError;
    }

    const { data: user, error } = await supabase
      .from("users")
      .select("push_tokens")
      .eq("id", customerId)
      .maybeSingle();

    if (error) {
      throw error;
    }

    const tokens = Array.isArray(user?.push_tokens)
      ? user.push_tokens.filter((value): value is string => Boolean(value))
      : [];

    if (tokens.length === 0) {
      return Response.json({ skipped: true, reason: "no_tokens" });
    }

    let payload: PushPayload;
    if (alertActivated) {
      const driverId = String(record.driver_id ?? "");
      let driverName = "";

      if (driverId) {
        const { data: driver, error: driverError } = await supabase
          .from("users")
          .select("name, role")
          .eq("id", driverId)
          .maybeSingle();

        if (driverError) {
          throw driverError;
        }

        if (driver?.role?.toString() === "driver") {
          driverName = String(driver.name ?? "").trim();
        }
      }

      const serviceType = inferServiceType(record);
      payload = {
        title: "Your order is here",
        body:
          serviceType === "delivery"
            ? driverName
              ? `${driverName} is here with your order. Attend your driver now.`
              : "Your driver is here. Attend your order now."
            : "Your order is ready for pickup now.",
        data: {
          eventType: "driver_arrival",
          orderId,
          orderStatus: nextStatus || previousStatus || "on_the_way",
          serviceType,
          driverName,
          screen: "orders",
        },
        channelId: "driver_arrival_alerts",
        includeNotification: false,
      };
    } else {
      const accessToken = await createGoogleAccessToken();
      const projectId = getEnv("FIREBASE_PROJECT_ID");
      const hasMultipleOrders = (orderCount ?? 0) > 1;
      payload = {
        title: "Order update",
        body: buildStatusNotificationBody(
          nextStatus,
          orderNumber,
          hasMultipleOrders,
        ),
        data: {
          eventType: "order_status",
          orderId,
          orderStatus: nextStatus,
          screen: "orders",
        },
        channelId: "order_updates",
      };

      const invalidTokens = new Set<string>();
      let sent = 0;
      let failed = 0;

      for (const token of tokens) {
        try {
          await sendPushToToken(accessToken, projectId, token, payload);
          sent += 1;
        } catch (error) {
          failed += 1;
          const message = error instanceof Error ? error.message : String(error);
          if (isTokenInvalidationError(message)) {
            invalidTokens.add(token);
          }
        }
      }

      if (invalidTokens.size > 0) {
        const filteredTokens = tokens.filter((token) => !invalidTokens.has(token));
        await supabase.from("users").update({ push_tokens: filteredTokens }).eq("id", customerId);
      }

      return Response.json({
        success: true,
        sent,
        failed,
        orderId,
        previousStatus,
        nextStatus,
        eventType: payload.data.eventType,
      });
    }

    const accessToken = await createGoogleAccessToken();
    const projectId = getEnv("FIREBASE_PROJECT_ID");
    const invalidTokens = new Set<string>();
    let sent = 0;
    let failed = 0;

    for (const token of tokens) {
      try {
        await sendPushToToken(accessToken, projectId, token, payload);
        sent += 1;
      } catch (error) {
        failed += 1;
        const message = error instanceof Error ? error.message : String(error);
        if (isTokenInvalidationError(message)) {
          invalidTokens.add(token);
        }
      }
    }

    if (invalidTokens.size > 0) {
      const filteredTokens = tokens.filter((token) => !invalidTokens.has(token));
      await supabase.from("users").update({ push_tokens: filteredTokens }).eq("id", customerId);
    }

    return Response.json({
      success: true,
      sent,
      failed,
      orderId,
      previousStatus,
      nextStatus,
      eventType: payload.data.eventType,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return Response.json({ error: message }, { status: 500 });
  }
});
